#!/bin/bash
# Exercises the planning engine off-device: the wind triangle, the vertical
# profile, stops and sectors, cross-track deviation, the fuel estimator and the
# approach geometry.
#
# These are the parts where being wrong is not a cosmetic bug — a fuel figure that
# is 35% low into a headwind is a real hazard — and they are pure Foundation +
# CoreLocation, so they can be compiled and run in a couple of seconds without a
# simulator. Stubs.swift stands in for the few app types they touch.
#
#   ./tools/planning-tests/run.sh
set -e
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
# Pull ArrivalPlanner out of the file it shares with its SwiftUI view.
python3 - "$OUT" <<'PY'
import io, sys
s = io.open('AeroMaps/InFlightAmendment.swift').read()
i = s.index('enum ArrivalPlanner'); j = s.index('// MARK: - The sheet')
io.open(sys.argv[1] + '/arrival.swift', 'w').write('import Foundation\nimport CoreLocation\n\n' + s[i:j])
PY
xcrun swiftc -O \
  AeroMaps/AltitudeProfile.swift \
  AeroMaps/Waypoint.swift \
  AeroMaps/WindModel.swift \
  AeroMaps/FlightRecord.swift \
  "$OUT/arrival.swift" \
  tools/planning-tests/Stubs.swift \
  tools/planning-tests/main.swift \
  -o "$OUT/planning-tests"
"$OUT/planning-tests"
