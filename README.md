# AeroMaps

Offline-first VFR flight planning for iOS — terrain-aware altitude profiles, real
airport and airspace data, live traffic. Built for GA pilots and flight instructors.

> **Not certified for navigation.** A planning aid, not a substitute for current
> charts, an official weather briefing, or NOTAMs.

---

## What it does

Plan a flight the way a pilot does: pick an aircraft, build a route, and get a
vertical profile computed from that airframe's actual numbers.

- **Build a route** from ICAO/IATA idents, coordinates in any of five formats
  (`37.62,-122.38`, `N37 37.2 W122 22.7`, `3737N12222W`, …), place search, a pasted
  route string (`KSFO KSJC KLAS`), or press-and-hold on the map.
- **Vertical profile** — climb, cruise and descent at the selected aircraft's rates
  and speeds, with terrain sampled underneath. Top of climb, top of descent, per-leg
  time and fuel, and a cruise altitude suggested from terrain clearance plus the VFR
  hemispherical rule.
- **Route Advisor** — generate a route, compare alternatives, and check the finished
  plan against terrain clearance, VFR cruising altitudes, controlled airspace, fuel
  reserves and aircraft limits.
- **Procedure Advisor** — runway selection from the reported surface wind and
  published runway headings, pattern altitudes, TOD distance and field frequencies.
- **Aircraft profiles** — six built-in types plus your own, by tail number. Cruise
  speed, climb and descent rates, ceiling, burn and usable fuel all feed the plan.
- **Live traffic**, airport diagrams, checklists, weight & balance, scratchpad.

## Data sources

Everything is public and needs no key. Anything the app cannot verify says so
rather than being filled in — see [Data honesty](#data-honesty).

| Data | Source | Notes |
|---|---|---|
| Airports, runways, frequencies, navaids | [OurAirports](https://ourairports.com/data/) | Public domain. ~29,000 airports, ~11,000 navaids. **Bundled — works offline.** |
| METAR / TAF / AIRMET / SIGMET | [NOAA Aviation Weather Center](https://aviationweather.gov/data/api/) | Official FAA/NWS, worldwide, no key |
| Controlled airspace | [FAA AIS](https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services/Class_Airspace/FeatureServer) | Published Class B/C/D/E. **US only.** Rate limited |
| Terrain elevation | [Open-Meteo](https://open-meteo.com/) | No key |
| Live traffic | [OpenSky Network](https://openskynetwork.github.io/opensky-api/) | Anonymous: 400 credits/day **per device** |
| NOTAMs | — | **Not included.** No free, open NOTAM API exists; the FAA's is approval-gated. See [API credentials](#api-credentials) |

Everything fetched is cached to disk with its age recorded, so a briefing taken on
the ground stays readable in the air.

## Building

**Requirements:** Xcode 16 or later. Deployment target is iOS 17, so the app runs
on iOS 17 and later.

Xcode 26+ additionally compiles the Liquid Glass surfaces; on older Xcode those
fall back to standard materials via a `#if compiler(>=6.2)` guard, and the app
looks and behaves the same minus the refraction. Nothing else in the project needs
a recent SDK.

```bash
git clone git@github.com:yuktachikate/AeroMaps_IOS.git
cd AeroMaps_IOS
open AeroMaps.xcodeproj
```

There is one target and one scheme, both named **AeroMaps**. No package manager, no
dependencies to resolve, nothing to install.

### In Xcode

1. Select the **AeroMaps** scheme and any iOS simulator.
2. **⌘R**.

That is the whole loop for simulator work — no signing needed.

**To run on a device**, set your own signing first. The project ships with an empty
team and a placeholder bundle identifier, so you must set both:

1. Select the project → **AeroMaps** target → **Signing & Capabilities**.
2. Set **Team** to your own Apple developer team.
3. Change **Bundle Identifier** from `com.example.AeroMaps` to something unique to
   you, e.g. `com.yourname.AeroMaps` — two people cannot install the same
   identifier on the same device.

Do not commit either change: keep them local, or set them in an untracked
`Secrets.xcconfig` alongside the API credentials below.

### From the command line

Useful for CI, or when Xcode is installed somewhere non-standard (a beta, say):

```bash
# If your Xcode is not the one xcode-select points at:
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild -project AeroMaps.xcodeproj -scheme AeroMaps -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

Install and launch on a booted simulator:

```bash
xcrun simctl install booted <DerivedData>/Build/Products/Debug-iphonesimulator/AeroMaps.app
xcrun simctl launch booted com.example.AeroMaps
```

### First run

- The app asks for **location** once, to show your position and the airports near
  you. It works without it, anchoring on the map view instead.
- The airport database is bundled, so the map and route planning work **with no
  network at all**. Weather, traffic and airspace need a connection and degrade to
  cached-or-absent without one, always labelled with their age.
- To see the local-flying features, set a simulator location:
  **Features → Location → Custom Location** (Palo Alto is `37.4611, -122.1150`).

### Troubleshooting

| Symptom | Cause |
|---|---|
| "Signing requires a development team" | Set your team and bundle ID as above, or build for a simulator with `CODE_SIGNING_ALLOWED=NO` |
| `xcodebuild: command not found`, or the wrong Xcode | `export DEVELOPER_DIR=...` as above, or `sudo xcode-select -s /Applications/Xcode.app` |
| No airspace on the map | US only, and the FAA service is rate limited — it backs off 70 s after a rejection and retries |
| No weather | Needs a network; fields without reporting equipment genuinely have none |
| Empty traffic, or an orange "Simulated traffic" badge | OpenSky unreachable or the daily anonymous quota is spent |

### API credentials

**NOTAMs are not shipped.** There is no free, open NOTAM API — the FAA's is
approval-gated, the public search is bot-blocked, and every third-party source is
either paid or licensed against redistribution. The client is written and tested;
supply credentials and it activates, including the map layer, which stays hidden
until then.

Check Route still reports the omission, so nobody assumes the preflight check
covered NOTAMs. Everything else in the app is keyless.

1. Register at the [FAA API portal](https://portal.apic4e.faa.gov/) and request
   access to the NOTAM API (approval-based, free).
2. Create `Secrets.xcconfig` in the repo root — it is gitignored:

   ```
   FAA_NOTAM_CLIENT_ID = your_client_id
   FAA_NOTAM_CLIENT_SECRET = your_client_secret
   ```

3. Set it as the configuration file for the Debug and Release configurations in the
   project's Info tab.

`Info.plist` references these as `$(FAA_NOTAM_CLIENT_ID)` /
`$(FAA_NOTAM_CLIENT_SECRET)`. Never commit real values.

## Layout

```
AeroMaps/                  the iOS app
  AeronauticalData.swift        airport/navaid database, catalog, spatial index
  AeronauticalDataUpdater.swift on-device rebuild from OurAirports CSVs
  AltitudeProfile.swift         vertical profile engine: climb/cruise/descent
  RouteAssistant.swift          route generation + validation
  AviationWeatherService.swift  METAR/TAF/SIGMET from NOAA
  AirspaceService.swift         FAA controlled airspace
  DataCache.swift               disk+memory cache, offline-first
  Surfaces.swift                material policy, Liquid Glass, sunlight mode
  Resources/aerodata.json       generated — see below
tools/
  build_airport_data.py    regenerates aerodata.json from OurAirports
backend/                   FastAPI service for prompt-tree tracing (not required to run the app)
frontend/                  React viewer for those traces (not required to run the app)
```

The app does not talk to `backend/`. Both exist for a separate tracing experiment
and can be ignored if you are working on the iOS side.

### Regenerating the airport database

`AeroMaps/Resources/aerodata.json` is **generated, never hand-edited**:

```bash
python3 tools/build_airport_data.py
```

The app also rebuilds it on device — same transform, same output — weekly over
Wi-Fi, so a shipped build stays current without anything being hosted. That path
takes about 1.6 s.

## Data honesty

The rule throughout: **never present data the app cannot stand behind.**

- Map-search results that aren't in the aeronautical database are marked unverified
  and excluded from briefings, generated checkpoints and fuel stops.
- Traffic is badged **live**, **cached (n min old)**, or **simulated** — the last
  when the OpenSky feed is unavailable and positions are locally generated.
- Runway headings come from published data, never derived from the designation
  (KSFO's 28R is 298°T, not 280° — an 18° error straight into the crosswind split).
- NOTAMs are absent and labelled absent without credentials.
- Fields with no reporting equipment show no weather rather than a plausible guess.

If you add a data source, keep this property. It is the difference between a
planning aid and a hazard.

## Known gaps

- **NOTAMs are not included.** The client exists but has no reachable free source;
  the layer is hidden and Check Route discloses the gap.
- **Airspace is US-only** — no free worldwide source exists (openAIP is gated and
  non-commercial).
- **Approach plates** are not included; the Airport Diagram is drawn from runway
  data, not FAA charts.
- **Winds aloft** above 3,000 ft still use a positional model when no station is
  reporting; surface wind is real.
- **Weight & balance** uses a fixed empty weight rather than a per-airframe figure.
- `FFMClient` returns bundled mock JSON.

## Contributing

Match the surrounding style. Two conventions worth knowing:

- **Comments explain why, not what.** Several non-obvious constraints are recorded
  in comments at the point they matter — the rasterised map symbols, the airspace
  cache grid, the CSV parser. Those exist because the naive version was tried and
  was wrong.
- **Anything fetched goes through `DataCache`** so it degrades to stale-but-real
  offline rather than to nothing.
