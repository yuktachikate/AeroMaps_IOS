import Foundation
import CoreLocation

// MARK: - Waypoint

/// How a waypoint got onto the route. Drives the icon shown next to it and
/// whether the altitude engine treats it as a field (elevation-anchored) or an
/// en-route fix (free to sit at cruise).
enum WaypointKind: String, Codable, Hashable {
    case airport
    case coordinate
    case place
    case mapPoint

    var symbolName: String {
        switch self {
        case .airport:    return "airplane.circle.fill"
        case .coordinate: return "scope"
        case .place:      return "mappin.circle.fill"
        case .mapPoint:   return "hand.tap.fill"
        }
    }

    var label: String {
        switch self {
        case .airport:    return "Airport"
        case .coordinate: return "Coordinate"
        case .place:      return "Place"
        case .mapPoint:   return "Map point"
        }
    }
}

/// A single point on the planned route.
///
/// `icao` is kept as an alias for `ident` because the map layer, the navigation
/// HUD and the saved-route library all address waypoints by that name.
struct Waypoint: Identifiable, Hashable {
    var id = UUID()
    var ident: String
    var name: String
    var coordinate: CLLocationCoordinate2D
    var kind: WaypointKind = .mapPoint

    /// Field elevation in feet MSL. Known for airports, nil elsewhere.
    var fieldElevationFT: Int?

    /// Pilot-entered altitude for this point. `nil` means "let the profile engine
    /// decide", which is the default — see `AltitudeProfile`.
    var plannedAltitudeFT: Int?

    /// Set when this waypoint came from the airport database, so detail views can
    /// look the full record back up.
    var airportICAO: String?

    /// Why a generated waypoint exists. A point on a route should earn its place —
    /// a level change, terrain, fuel — and this is the reason shown to the pilot.
    /// Nil for points the pilot placed themselves.
    var reason: String?

    var icao: String { ident }

    var isAltitudeManual: Bool { plannedAltitudeFT != nil }

    var subtitle: String {
        if !name.isEmpty && name != ident { return name }
        return Self.formatCoordinate(coordinate)
    }

    init(id: UUID = UUID(),
         ident: String,
         name: String = "",
         coordinate: CLLocationCoordinate2D,
         kind: WaypointKind = .mapPoint,
         fieldElevationFT: Int? = nil,
         plannedAltitudeFT: Int? = nil,
         airportICAO: String? = nil,
         reason: String? = nil) {
        self.id = id
        self.ident = ident
        self.name = name.isEmpty ? ident : name
        self.coordinate = coordinate
        self.kind = kind
        self.fieldElevationFT = fieldElevationFT
        self.plannedAltitudeFT = plannedAltitudeFT
        self.airportICAO = airportICAO
        self.reason = reason
    }

    init(airport: Airport) {
        self.init(ident: airport.icao,
                  name: airport.name,
                  coordinate: airport.coordinate,
                  kind: .airport,
                  fieldElevationFT: airport.elevation,
                  airportICAO: airport.icao)
    }

    func withReason(_ reason: String) -> Waypoint {
        var copy = self
        copy.reason = reason
        return copy
    }

    static func == (lhs: Waypoint, rhs: Waypoint) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// "N37°37.28' W122°22.74'" — the aviation-style format pilots read back.
    static func formatCoordinate(_ c: CLLocationCoordinate2D) -> String {
        func part(_ value: Double, positive: String, negative: String) -> String {
            let hemi = value >= 0 ? positive : negative
            let abs = Swift.abs(value)
            let deg = Int(abs)
            let minutes = (abs - Double(deg)) * 60
            return String(format: "%@%d°%05.2f'", hemi, deg, minutes)
        }
        return "\(part(c.latitude, positive: "N", negative: "S")) \(part(c.longitude, positive: "E", negative: "W"))"
    }
}

// MARK: - Coordinate parsing

/// Parses the coordinate formats a pilot might actually type.
///
/// Accepted, in the order they are tried:
///   decimal pair       `37.62, -122.38`  `37.62 -122.38`  `37.62/-122.38`
///   signed with hemi   `N37.62 W122.38`  `37.62N 122.38W`
///   degrees-minutes    `N37 37.2 W122 22.7`  `3737.2N/12222.7W`
///   deg-min-sec        `37°37'16"N 122°22'44"W`
///   ICAO shorthand     `3737N12222W`
enum CoordinateParser {

    static func parse(_ raw: String) -> CLLocationCoordinate2D? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !text.isEmpty else { return nil }

        for parser in [parseShorthand, parseHemisphereGroups, parseDecimalPair] {
            if let c = parser(text), isValid(c) { return c }
        }
        return nil
    }

    private static func isValid(_ c: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(c) && abs(c.latitude) <= 90 && abs(c.longitude) <= 180
        && !(c.latitude == 0 && c.longitude == 0)
    }

    /// `37.62, -122.38` and friends — two bare signed decimals.
    private static func parseDecimalPair(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(whereSeparator: { ",/ ".contains($0) })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard parts.count == 2,
              let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// `3737N12222W` / `N3737W12222` — packed DDMM with no separators.
    private static func parseShorthand(_ text: String) -> CLLocationCoordinate2D? {
        let compact = text.filter { !" ,/".contains($0) }
        let pattern = #"^([NS])?(\d{4})([NS])?([EW])?(\d{5})([EW])?$"#
        guard let m = firstMatch(pattern, in: compact) else { return nil }

        let latHemi = m[1].isEmpty ? m[3] : m[1]
        let lonHemi = m[4].isEmpty ? m[6] : m[4]
        guard !latHemi.isEmpty, !lonHemi.isEmpty else { return nil }

        guard let latDeg = Double(m[2].prefix(2)), let latMin = Double(m[2].suffix(2)),
              let lonDeg = Double(m[5].prefix(3)), let lonMin = Double(m[5].suffix(2)) else { return nil }

        let lat = (latDeg + latMin / 60) * (latHemi == "S" ? -1 : 1)
        let lon = (lonDeg + lonMin / 60) * (lonHemi == "W" ? -1 : 1)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Anything with explicit N/S/E/W markers and one to three numeric groups per
    /// axis: covers `N37 37.2 W122 22.7` and `37°37'16"N 122°22'44"W`.
    private static func parseHemisphereGroups(_ text: String) -> CLLocationCoordinate2D? {
        // Split into a latitude chunk and a longitude chunk around the hemisphere letters.
        let normalized = text.replacingOccurrences(of: "°", with: " ")
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "/", with: " ")

        var latValue: Double?
        var lonValue: Double?
        var pending: [Double] = []
        var pendingHemi: String?

        func flush() {
            guard let hemi = pendingHemi, !pending.isEmpty else { pending = []; return }
            var value = pending[0]
            if pending.count > 1 { value += pending[1] / 60 }
            if pending.count > 2 { value += pending[2] / 3600 }
            if hemi == "S" || hemi == "W" { value = -value }
            if hemi == "N" || hemi == "S" { latValue = value } else { lonValue = value }
            pending = []
            pendingHemi = nil
        }

        // Tokenise into numbers and hemisphere letters, tolerating "37.62N" runs.
        var buffer = ""
        func drainBuffer() {
            if let d = Double(buffer) { pending.append(d) }
            buffer = ""
        }
        for ch in normalized {
            if ch.isNumber || ch == "." || ch == "-" {
                buffer.append(ch)
            } else if "NSEW".contains(ch) {
                drainBuffer()
                if pendingHemi != nil { flush() }
                pendingHemi = String(ch)
                // A leading hemisphere letter (N37 …) keeps collecting; a trailing
                // one (37N …) closes the group immediately.
                if !pending.isEmpty { flush() }
            } else {
                drainBuffer()
            }
        }
        drainBuffer()
        flush()

        guard let lat = latValue, let lon = lonValue else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            guard let r = Range(m.range(at: i), in: text) else { return "" }
            return String(text[r])
        }
    }
}

// MARK: - Route string parsing

/// Turns a whitespace-separated route string into waypoints — the way flight
/// planning tools accept "KSFO KSJC 3730N12210W KLAS" in one field.
enum RouteStringParser {

    struct Token {
        let text: String
        let waypoint: Waypoint?
    }

    /// Resolves each token against the airport table first, then the coordinate
    /// parsers. Tokens that resolve to neither come back with a nil waypoint so
    /// the caller can report exactly which ones failed.
    static func parse(_ text: String, airports: AirportCatalog) -> [Token] {
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return tokens.map { token in
            let key = token.uppercased()
            if let airport = airports[key] ?? airports["K" + key] {
                return Token(text: token, waypoint: Waypoint(airport: airport))
            }
            if let coord = CoordinateParser.parse(token) {
                return Token(text: token,
                             waypoint: Waypoint(ident: Waypoint.formatCoordinate(coord),
                                                name: "Coordinate",
                                                coordinate: coord,
                                                kind: .coordinate))
            }
            return Token(text: token, waypoint: nil)
        }
    }
}
