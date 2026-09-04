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
| NOTAMs | [FAA NOTAM API](https://external-api.faa.gov/notamapi/v1/) | **Requires credentials** — see below |

Everything fetched is cached to disk with its age recorded, so a briefing taken on
the ground stays readable in the air.

## Getting started

```bash
git clone git@github.com:yuktachikate/AeroMaps_IOS.git
cd AeroMaps_IOS
open AeroMaps.xcodeproj
```

Build and run. No package manager, no dependencies, no signing setup beyond your
own team. The airport database ships in the repo, so it works on first launch with
no network.

**Requirements:** Xcode 26+ (iOS 26 SDK for the Liquid Glass APIs), deployment
target iOS 17.

### API credentials

Only NOTAMs need credentials; everything else is keyless. Without them the app
reports NOTAMs as unavailable and never fabricates any.

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

- **NOTAMs** need FAA credentials; there is no free, open NOTAM API.
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
