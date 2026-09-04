# AeroMaps and the Prompt Tree Explorer: System Design and Integration

**Document:** AeroMaps-DD-01
**Status:** Draft for research
**Date:** 2026-08-05
**Scope:** iOS aviation app and LLM trace explorer

---

## 00. Executive summary

**AeroMaps** is an iOS aviation application built in SwiftUI and MapKit. It shows live air
traffic, aeronautical weather, airport data, and turn by turn route navigation, and it plans
flights through an on-device engine called FFM (Flight Feasibility and Metrics). The novel part
for a paper is not the map. It is that every FFM planning run is recorded as a structured decision
tree of typed nodes (agent, tool, policy, llm) with inputs, outputs, latency, status, and a plain
language narration, and the app ships a native SwiftUI visualizer that renders that tree inside the
product.

The **GenAI Prompt Tree Explorer** is a separate three tier tool for tracing multi step LLM
workflows. A Python SDK instruments functions with a `@trace_node` decorator, a FastAPI service
stores the resulting graph in SQLite, and a React plus React Flow web application draws the directed
acyclic graph so a developer can inspect, annotate, and flag nodes.

The two systems share a data model almost exactly. This document explains both in enough depth to
write about them, then specifies how the AeroMaps tracer can ship its planning traces into the
Explorer so a safety adjacent mobile agent becomes observable through the same lens used for cloud
LLM chains. That bridge is the research contribution.

| Piece | What it is |
| --- | --- |
| A. AeroMaps | SwiftUI and MapKit aviation app with an on-device FFM planning agent that emits decision traces. |
| B. Prompt tree layer | A Swift tracer and visualizer that models planning as typed nodes with parent links, latency, status, and narration. |
| C. Explorer | Python SDK, FastAPI store, React Flow DAG UI for tracing, annotating, and flagging LLM chains. |
| D. The bridge | One HTTP contract lets the app post its traces into the shared store, uniting on-device and cloud observability. |

---

## 01. AeroMaps: what it is

AeroMaps presents a pilot facing map with layered aeronautical information and a planning workflow
that moves through three modes: **plan**, **fly**, and **review**. A user drops waypoints, builds a
route, runs a safety plan, then follows turn by turn guidance as GPS advances progress along the legs.

### Technology and shape of the codebase

- **Platform.** Swift and SwiftUI for the interface, MapKit for the map surface, CoreLocation for
  GPS and heading. Deployment target iOS 17.
- **State.** A single large observable object, `MapState`, holds almost all application state and
  logic. Three services are injected app wide as environment objects: `LocationManager`,
  `WeatherService`, and `LiveFlightService`.
- **File shape.** The project is deliberately monolithic. `AeroMapsApp.swift` is about 1,320 lines
  and holds the entry point, every data model, `MapState`, `LocationManager`, and `WeatherService`.
  `ContentView.swift` is about 2,880 lines and holds all of the UI, the MapKit bridge, and the
  annotation and overlay rendering. `LiveFlightService.swift` is about 710 lines.

### Feature surface

- **Live traffic radar.** Real flights from the OpenSky Network with a procedural fallback fleet,
  moving once per second, with clustering and Flightradar24 style trails.
- **Route planning.** Waypoint drop, airport search, altitude and cruise selection, weight and
  balance, and a fuel and performance summary.
- **FFM safety planning.** On-device per leg scoring of icing, turbulence, and terrain, fuel reserve
  enforcement, and a pilot advisory, all recorded as a decision tree.
- **Weather briefing.** METAR, TAF, winds aloft, and radar tiles, currently simulated but structured
  for a real aviation weather feed.
- **Turn by turn navigation.** A GPS driven state machine that advances waypoints, computes cross
  track deviation, and shows a heads up guidance banner.
- **Decision tree visualizer.** A native view that renders the FFM planning trace so the reasoning
  behind a plan is inspectable inside the app.

---

## 02. Architecture and state model

### Dependency injection at launch

The `@main` entry point `AeroMapsApp` constructs the three services as state objects and injects them
into `ContentView` as environment objects, then requests location authorization. From there the
environment carries the services down into every tab and into the MapKit bridge.

### MapState as the single source of truth

`MapState` is an observable object of roughly 1,100 lines. It owns concerns that a larger codebase
would usually split apart.

| Concern | Representative state and methods |
| --- | --- |
| Camera and style | `camera`, `mapStyle`, `shouldCenterCamera`, `zoomToRoute()` |
| Tabs and sheets | `activeTab`, `flightSubTab`, `mode`, the `showing*` flags for airport, flight, planner, weather, prompt tree |
| Route and waypoints | `route: RoutePlan`, `addWaypoint()`, `clearRoute()`, `computedPolyline` |
| Navigation | `isNavigatingRoute`, `currentWaypointIndex`, `offRouteDistanceNM`, `updateLiveNavigationProgress()` |
| Saved routes | `savedRoutes`, `saveCurrentRoute()`, `loadSavedRoute()` |
| Selection and search | `selectedAirport`, `selectedFlight`, `performLiveAirportSearch()` |
| Layers | `activeLayers: Set<LayerKind>` persisted to UserDefaults, `riskOverlays` |
| Geometry | `distanceNM()`, `bearingDegrees()`, `calculateCrossTrackDeviation()` |
| Planning | `computeFFMPlan()`, `ffmAdvice`, `legRisks`, the airport catalog `airports` |

### The always mounted map

The map is expensive to build, so it is never torn down. `ContentView` keeps `MapTabView` mounted at
all times and toggles its opacity and hit testing, overlaying the other tabs on top with an opaque
background. Earlier the app rebuilt the `MKMapView` on every tab switch, which caused tile reloads and
a GL setup cost that felt like a freeze. Keeping it mounted removed that.

### The MapKit bridge and its diffing strategy

`MapView` is a `UIViewRepresentable` that wraps `MKMapView`, with a `Coordinator` acting as delegate.
Because `MapState` publishes frequently, `updateUIView` guards expensive work behind a change hash of
waypoints, layers, style, and navigation state. Live flight annotations, however, update every tick
through a diff keyed by `icao24` so planes move smoothly without rebuilding the overlay set.

> **Notable characteristics for a methods section.** The architecture is a unified fat state pattern:
> one giant observable object and two very large files. It trades modularity for co-located change and
> rapid iteration. Three engineering pressures show up repeatedly: MapKit reentrancy during clustering,
> SwiftUI observation feedback loops, and the cost of a once per second refresh across an always mounted
> map. These are concrete, citable examples of the friction of running an agentic, real time system on a
> phone.

---

## 03. Domain subsystems

### Live flight service

`LiveFlightService` is the radar. It queries the OpenSky Network `states/all` endpoint over a bounding
box capped at fifteen degrees, parses aircraft position, altitude, speed, and heading, and assigns
plausible origin and destination airports by region. When OpenSky returns no usable traffic, which is
common for an anonymous, rate limited client, it generates a procedural fleet around a catalog of
twenty four global hub airports, weighting dense corridors more heavily. A one second timer advances
every aircraft along its heading vector with a smooth boundary wrap. The `LiveFlight` model carries
`icao24`, `callsign`, `coordinate`, `altitude`, `speed`, `heading`, `verticalRate`, `origin`,
`destination`, `squawk`, and an `isTracked` flag. A recent addition records a `trailPoints` path for
the selected flight, capped at 240 points.

### FFM: the planning engine and the source of the trace

FFM stands for Flight Feasibility and Metrics. `FFMClient` models a request of aircraft performance, a
route, and a policy (reserve minutes, minimum en route altitude enforcement), and a response of a
computed polyline, per leg risk scores for icing, turbulence, and terrain, alternate airports, and a
pilot advisory. It can call a backend planning service or return a mock. The important method is
`MapState.computeFFMPlan()`, which runs the scoring on device and, as a side effect, records a prompt
tree session that captures the planning agent's reasoning. This is where the two systems in this
document meet.

### Route navigation state machine

Navigation is GPS driven. On every location fix, `updateLiveNavigationProgress()` projects the aircraft
onto the active leg, advances `currentWaypointIndex` forward only when the aircraft is within an
adaptive capture radius, and computes cross track deviation for an off route indicator. A completion
state keeps the flown route drawn until the pilot dismisses it.

### Weather, planner, and supporting views

- **WeatherService** polls on a sixty second interval and currently returns simulated METAR, TAF, wind,
  visibility, ceiling, temperature, and pressure keyed by airport, with the structure ready for a real
  feed.
- **FlightPlannerView** is the modal briefing: aircraft selection, pilot and passenger and fuel entry,
  weight and balance with a center of gravity check, and a performance and reserve summary, ending in
  start navigation or save.
- **AirportDetailView** shows runways, frequencies, services, and live weather. **BottomSheet** hosts
  search, layer toggles, waypoint chips, and the confirm plan actions.

> **Real vs simulated, state this plainly in the paper.** Real data: OpenSky live positions when
> available, device GPS, and Apple local search for airports. Simulated: the fallback fleet, all
> weather, and optionally the FFM plan. Any evaluation must separate claims about the observability
> method, which holds regardless, from claims about data fidelity, which does not.

---

## 04. The prompt tree layer

Two Swift files implement an in app tracer and visualizer. They are the conceptual seed of the whole
integration, because they model an on-device decision the same way an LLM tracing SDK models a cloud
chain.

### The Swift node model

`PromptTreeTracer` is an observable singleton holding `sessions` and an `activeSession`. A session has
an id, a title such as `FFM Plan: KSFO -> KSJC`, a timestamp, and a flat array of nodes linked by
parent id. Each node is:

```swift
// PromptTreeTracer.swift
struct PromptTreeNode: Identifiable, Codable {
    let id: String            // unique node id
    let parentId: String?     // null at the root
    let name: String          // e.g. "FFM_Risk_Planning_Agent"
    let nodeType: String      // "agent" | "tool" | "llm" | "policy"
    let inputs: String        // human readable context
    let outputs: String       // result text
    let latencyMs: Double     // wall clock latency
    let narration: String     // agent explanation of its own step
    let status: String        // "success" | "warning" | "error"
    let timestamp: Date
}
```

Tracing is manual and imperative rather than decorator based. `computeFFMPlan()` builds a root `agent`
node and three children (a `tool` node for geometry, a `policy` node for reserve and altitude checks,
and an `llm` node for advisory synthesis, marked `warning` when risk is elevated), then calls
`recordSession(title:nodes:)`. There is no real language model in the loop today. The tracer is a
faithful recorder of a deterministic planning agent, which is ideal for a controlled study.

### The visualizer

`PromptTreeVisualizerView` renders the tree with a recursive `NodeTreeCard` that filters children by
parent id and indents each generation, coloring and icon coding by node type, with a read only
inspector that shows narration, inputs, and outputs. It opens from a menu section titled AI Safety and
Diagnostics and from a sheet bound to `showingPromptTree`.

> **Why this matters.** The app does not just plan a flight. It exposes why it planned that flight as a
> structured, typed, inspectable artifact. That reframes a mobile utility as an early example of built
> in agent observability in a domain where explaining a recommendation carries real weight.

---

## 05. GenAI Prompt Tree Explorer

The Explorer is the tool to integrate. It decouples into a client SDK, an ingestion API, and a
visualization UI.

- **SDK (Python).** A `Tracer` session plus a `@trace_node` decorator. Parent and child links are
  inferred automatically through `contextvars`. A daemon thread ships nodes so the host app never blocks.
- **API (FastAPI plus SQLite).** Ingests nodes, serves a session as a node list, and accepts
  annotations. Graph edges are stored as a parent id column. CORS is open.
- **UI (React Flow).** Polls the API, maps nodes to a graph, lays it out with dagre, and renders a
  custom node with latency, tokens, error, and flag states. Includes annotation and voice narration.

### The wire contract

A traced Python function emits one JSON node per call. The SDK captures inputs by binding the function
signature, estimates a token count from output length, times the call, and records any exception, then
enqueues the payload for the background worker.

```jsonc
// POST {api_host}/api/v1/traces  (one node per call)
{
  "node_id": "uuid4",
  "parent_id": "uuid4 | null",   // tree edge, set via contextvars
  "session_id": "RAG_QA_1a2b3c4d",
  "name": "Extract_Context",
  "node_type": "llm_call",       // llm_call | tool | logic | ...
  "inputs": { "query": "..." },
  "outputs": "...",
  "start_time": 1723000000.12,
  "end_time": 1723000000.34,
  "latency_ms": 220.0,
  "token_count": 57,
  "error": null,
  "metadata": {}
}
```

### Endpoints and store

| Method and path | Purpose |
| --- | --- |
| `POST /api/v1/traces` | Ingest a single node, generating a node id if absent. |
| `POST /api/v1/import_traces` | Bulk upsert a list of nodes with INSERT OR REPLACE. The natural seam for a mobile client. |
| `GET /api/v1/trees/{session_id}` | Return all nodes in a session ordered by start time. |
| `PATCH /api/v1/nodes/{node_id}` | Set annotations text and the flagged boolean. |
| `GET /api/v1/sessions` | List distinct session ids, newest first. |
| `POST /api/v1/run_demo` | Spawn a demo agent to populate the store. |

The store is a single SQLite `traces` table keyed by `node_id`, with `parent_id` for edges, JSON text
for `inputs`, `outputs`, and `metadata`, and `annotations` and `flagged` columns for human review. The
frontend polls the tree every few seconds, converts the node list into React Flow nodes and edges, lays
it out with dagre top to bottom, and colors each node by status, marking errors with a red border and
flagged nodes with a ring.

> **One reconciliation before wiring.** The SDK defaults its host to port 8000 while the README and the
> frontend expect 8081. Any real integration should fix the host and port in one place.

---

## 06. Integration design

The two node models are close enough that integration is mostly a mapping plus a small HTTP client. The
plan keeps the app authoritative for producing traces and lets the Explorer become the shared,
annotatable view across on-device and cloud runs.

### Field mapping

| Swift PromptTreeNode | Explorer field | Status |
| --- | --- | --- |
| `id` | `node_id` | direct |
| `parentId` | `parent_id` | direct |
| session id (on `PromptTreeSession`) | `session_id` | direct |
| `name` | `name` | direct |
| `nodeType` | `node_type` | compatible, both free strings |
| `inputs` / `outputs` (String) | `inputs` (dict) / `outputs` (any) | wrap the string as JSON |
| `latencyMs` | `latency_ms` | direct |
| `timestamp` | `start_time` (derive `end_time`) | compute from latency |
| `status` | `error` plus node styling | map warning and error to error text |
| `narration` | `metadata.narration` | the UI can read it aloud |
| none today | `token_count` | add when a real model is used |
| none today | `annotations` / `flagged` | write path only, back from the UI |

The narration mapping is the pleasing part. The Swift model carries a first person explanation per node,
and the Explorer frontend already reads `metadata.narration` for its voice narration feature, so the
app's explanations flow straight into an accessible readout.

### A Codable payload and one client call

The app converts each session to the Explorer contract and posts the batch to `import_traces`. No SDK
port is required.

```swift
// Proposed: PromptTreeExporter.swift
struct ExplorerNode: Codable {
  let session_id, node_id, name, node_type: String
  let parent_id: String?
  let inputs: [String: String]     // {"context": inputs}
  let outputs: String
  let start_time, latency_ms: Double
  let error: String?               // nil unless status == "error"
  let metadata: [String: String]   // {"narration": ..., "status": ...}
}

// POST [ExplorerNode] to {host}/api/v1/import_traces after computeFFMPlan()
```

### Phased plan

1. **Export.** Map sessions to the contract and bulk post to the running Explorer. Read only, no app UI
   change.
2. **Enrich.** Add token counts and precise start and end times, and split status into a clean error
   field.
3. **Round trip.** Pull annotations and flags back so a reviewer's notes appear next to the plan in the
   app.
4. **Real agent.** Replace the deterministic advisory node with an actual model call and trace it end to
   end.

> **Design guardrails.** Keep the Swift model as source of truth and treat the Explorer contract as an
> export format, so the app is not coupled to the tool. Send on a background task with silent failure,
> exactly as the app already ships live telemetry, so tracing never affects flight facing latency. Mask
> any user identifying fields before export, since the backend has no auth.

---

## 07. Research framing

### Problem statement

Agentic software is moving onto devices and into domains where a recommendation must be explainable, not
just produced. Existing LLM observability tools assume a cloud, Python, server logged setting. There is
little work on tracing and reviewing an agent that runs on a phone, mixes deterministic policy with
model calls, and operates in a safety adjacent context such as aviation. AeroMaps plus the Explorer is a
concrete testbed for that gap.

### Contributions a paper could claim

1. A unified node model that represents both a deterministic on-device planning agent and a cloud LLM
   chain, shown to interoperate through a single import contract.
2. A pattern for in product agent observability, where the reasoning tree is a first class, inspectable
   artifact rather than a hidden log.
3. A study of the engineering constraints of real time agent tracing on a mobile platform, grounded in
   concrete failure modes: view update feedback loops, map clustering reentrancy, and refresh cost.
4. The narration channel as a bridge to accessibility, where an agent's per step self explanation drives
   a spoken readout in the shared viewer.

### Evaluation directions

- **Interoperability.** Show that traces produced on device render and annotate identically to cloud
  traces in the same Explorer session view.
- **Overhead.** Measure added latency and battery from tracing during planning and navigation, arguing
  the background, fire and forget design keeps it negligible.
- **Comprehension.** A small user study on whether the decision tree helps a pilot or developer
  understand and trust a plan compared with the advisory text alone.
- **Review workflow.** Whether flags and annotations round tripped from the Explorer improve iteration on
  the planning policy.

### Limitations to disclose

Weather and the fallback fleet are simulated, the FFM advisory is deterministic rather than a live model
today, and the Explorer backend has open CORS and no authentication. These bound the fidelity claims but
not the observability method, and each maps to a clear item on the phased plan above.

---

## Appendix A. File and symbol map

| Symbol | Location | Role |
| --- | --- | --- |
| `AeroMapsApp` | AeroMapsApp.swift:6 | Entry point, service injection |
| `MapState` | AeroMapsApp.swift:251 | Central observable state, about 1,100 lines |
| `computeFFMPlan()` | AeroMapsApp.swift:1128 | On-device planning, emits the trace session |
| `LocationManager` / `WeatherService` | AeroMapsApp.swift:1284 / 1241 | GPS and heading, weather polling |
| `LiveFlightService` | LiveFlightService.swift:94 | OpenSky feed, fallback fleet, trails |
| `MapView` / `Coordinator` | ContentView.swift:792 / 1245 | MapKit bridge, annotation and overlay rendering |
| `PromptTreeNode` / `PromptTreeTracer` | PromptTreeTracer.swift:7 / 29 | Trace model and recorder |
| `PromptTreeVisualizerView` | PromptTreeVisualizerView.swift:5 | Native decision tree view |
| `Tracer` / `@trace_node` | Explorer sdk/prompt_tree.py | Python instrumentation |
| FastAPI app | Explorer backend/app/main.py | Ingest, serve, annotate |
| React Flow UI | Explorer frontend/src | DAG layout and review |
