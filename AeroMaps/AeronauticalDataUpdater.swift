import Foundation

/// Rebuilds the bundled aeronautical dataset on the device, from OurAirports.
///
/// The app deliberately depends on no server of its own. Rather than fetch a
/// pre-built file from somewhere that would have to be hosted and maintained, this
/// downloads the same public-domain CSVs the build script uses and performs the
/// identical transform on the phone. The output is byte-compatible with the
/// bundled `aerodata.json`, so the loader cannot tell which produced it.
///
/// It is a background, Wi-Fi-preferred, occasional job: roughly 19 MB of CSV in,
/// about 8 MB of JSON out, and the working copy is only replaced once the new one
/// has parsed and passed a sanity check.
enum AeronauticalDataUpdater {

    private static let base = "https://davidmegginson.github.io/ourairports-data"

    /// Below this the download is assumed to have gone wrong and the existing copy
    /// is kept. The real figure is around 29,000.
    private static let minimumPlausibleAirports = 20_000

    enum UpdateError: Error {
        case network(String)
        case implausibleResult(airports: Int)
    }

    struct Progress {
        let stage: String
        let fraction: Double
    }

    /// Downloads, parses and returns the encoded dataset. Does not touch disk — the
    /// caller decides whether to adopt it.
    ///
    /// All four files are fetched and parsed concurrently. They are independent
    /// until the merge at the end, so there is no reason to do them in turn, and
    /// Swift's cooperative pool spreads the parsing across cores.
    static func buildDataset(onProgress: ((Progress) -> Void)? = nil) async throws -> Data {
        onProgress?(Progress(stage: "Downloading", fraction: 0.05))

        async let airportsData = fetch("airports.csv")
        async let runwaysData = fetch("runways.csv")
        async let frequenciesData = fetch("airport-frequencies.csv")
        async let navaidsData = fetch("navaids.csv")

        let (rawAirports, rawRunways, rawFrequencies, rawNavaids) =
            try await (airportsData, runwaysData, frequenciesData, navaidsData)

        onProgress?(Progress(stage: "Parsing", fraction: 0.55))

        // Parsed in parallel into independent structures, merged afterwards.
        async let parsedAirports = Task.detached(priority: .utility) { parseAirports(rawAirports) }.value
        async let parsedRunways = Task.detached(priority: .utility) { parseRunways(rawRunways) }.value
        async let parsedFrequencies = Task.detached(priority: .utility) { parseFrequencies(rawFrequencies) }.value
        async let parsedNavaids = Task.detached(priority: .utility) { parseNavaids(rawNavaids) }.value

        var airports = await parsedAirports
        let runways = await parsedRunways
        let frequencies = await parsedFrequencies
        let navaids = await parsedNavaids

        guard airports.count >= minimumPlausibleAirports else {
            throw UpdateError.implausibleResult(airports: airports.count)
        }

        onProgress?(Progress(stage: "Merging", fraction: 0.85))
        for (ident, list) in runways where airports[ident] != nil { airports[ident]?.R = list }
        for (ident, list) in frequencies where airports[ident] != nil { airports[ident]?.F = list }

        onProgress?(Progress(stage: "Saving", fraction: 0.95))
        let file = AeroFile(
            version: 1,
            generated: ISO8601DateFormatter().string(from: Date()),
            source: "OurAirports (public domain) — ourairports.com/data/",
            airports: airports.values.sorted { $0.i < $1.i },
            navaids: navaids.sorted { $0.i < $1.i })

        let data = try JSONEncoder().encode(file)
        onProgress?(Progress(stage: "Done", fraction: 1))
        return data
    }

    // MARK: Fetching

    private static func fetch(_ file: String) async throws -> Data {
        guard let url = URL(string: "\(base)/\(file)") else { throw UpdateError.network(file) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        // A ~19 MB refresh is not worth a cellular bill or a hotspot allowance.
        request.allowsExpensiveNetworkAccess = false
        request.allowsConstrainedNetworkAccess = false

        // Bulk rather than URLSession.bytes(...).lines: the byte-at-a-time async
        // sequence measured about four times slower on a desktop and considerably
        // worse on phone cores, and 12.7 MB in memory is not a problem.
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.network("\(file) returned \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return data
    }

    // MARK: Parsing

    /// Heliports, seaplane bases, balloonports and closed fields are excluded: none
    /// is somewhere a training flight or a local hop plans a leg to.
    private static let keptTypes: [String: Int] = [
        "large_airport": 3, "medium_airport": 2, "small_airport": 1
    ]

    private static func parseAirports(_ data: Data) -> [String: AeroFile.Airport] {
        var out: [String: AeroFile.Airport] = [:]
        out.reserveCapacity(30_000)

        forEachRow(data) { columns, fields in
            guard let typeCode = keptTypes[fields[columns["type"]]] else { return }
            let ident = fields[columns["ident"]].uppercased()
            // A four-character ident is what a pilot files and what lookup uses.
            guard ident.count == 4, ident.allSatisfy({ $0.isLetter || $0.isNumber }) else { return }

            out[ident] = AeroFile.Airport(
                i: ident,
                n: String(fields[columns["name"]].prefix(60)),
                m: String(fields[columns["municipality"]].prefix(40)),
                r: String(fields[columns["iso_region"]].split(separator: "-").last?.prefix(6) ?? ""),
                c: fields[columns["iso_country"]],
                t: typeCode,
                y: Double(fields[columns["latitude_deg"]]) ?? 0,
                x: Double(fields[columns["longitude_deg"]]) ?? 0,
                e: Int(Double(fields[columns["elevation_ft"]]) ?? 0),
                a: fields[columns["iata_code"]].uppercased(),
                R: [], F: [])
        }
        return out
    }

    private static func parseRunways(_ data: Data) -> [String: [AeroFile.Runway]] {
        var out: [String: [AeroFile.Runway]] = [:]
        forEachRow(data) { columns, fields in
            guard fields[columns["closed"]] != "1" else { return }
            let ident = fields[columns["airport_ident"]].uppercased()
            guard !ident.isEmpty else { return }

            let low = fields[columns["le_ident"]], high = fields[columns["he_ident"]]
            guard !low.isEmpty || !high.isEmpty else { return }

            out[ident, default: []].append(AeroFile.Runway(
                d: !low.isEmpty && !high.isEmpty ? "\(low)/\(high)" : (low.isEmpty ? high : low),
                l: Int(Double(fields[columns["length_ft"]]) ?? 0),
                w: Int(Double(fields[columns["width_ft"]]) ?? 0),
                s: surfaceName(fields[columns["surface"]]),
                g: fields[columns["lighted"]] == "1",
                // Published true headings. Deriving them from the designation
                // ("28R" → 280°) is wrong by a few degrees — KSFO's 28R is 298°T —
                // and that error lands straight in the crosswind component.
                hl: Double(fields[columns["le_heading_degT"]]),
                hh: Double(fields[columns["he_heading_degT"]])))
        }
        return out
    }

    private static func parseFrequencies(_ data: Data) -> [String: [AeroFile.Frequency]] {
        var out: [String: [AeroFile.Frequency]] = [:]
        forEachRow(data) { columns, fields in
            let ident = fields[columns["airport_ident"]].uppercased()
            guard !ident.isEmpty, let mhz = Double(fields[columns["frequency_mhz"]]), mhz > 0 else { return }
            var text = String(format: "%.3f", mhz)
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
            out[ident, default: []].append(
                AeroFile.Frequency(t: String(fields[columns["type"]].prefix(8)), f: text))
        }
        return out
    }

    private static func parseNavaids(_ data: Data) -> [AeroFile.Navaid] {
        var out: [AeroFile.Navaid] = []
        out.reserveCapacity(12_000)
        forEachRow(data) { columns, fields in
            let ident = fields[columns["ident"]].uppercased()
            guard !ident.isEmpty else { return }
            let khz = Double(fields[columns["frequency_khz"]]) ?? 0
            out.append(AeroFile.Navaid(
                i: ident,
                n: String(fields[columns["name"]].prefix(40)),
                t: String(fields[columns["type"]].prefix(8)),
                y: Double(fields[columns["latitude_deg"]]) ?? 0,
                x: Double(fields[columns["longitude_deg"]]) ?? 0,
                c: fields[columns["iso_country"]],
                f: khz > 0 ? (khz / 1000).rounded(toPlaces: 3) : nil))
        }
        return out
    }

    private static let surfaces: [String: String] = [
        "ASP": "Asphalt", "ASPH": "Asphalt", "CON": "Concrete", "CONC": "Concrete",
        "GRS": "Grass", "GRASS": "Grass", "TURF": "Turf", "GVL": "Gravel",
        "GRVL": "Gravel", "DIRT": "Dirt", "WATER": "Water", "SAND": "Sand",
        "PEM": "Asphalt", "MAC": "Macadam", "COP": "Composite", "SNOW": "Snow"
    ]

    private static func surfaceName(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if let known = surfaces[key] { return known }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Unknown" : trimmed.capitalized
    }

    // MARK: CSV

    /// Column name to position, resolved once from the header.
    ///
    /// The previous version built a `[String: String]` dictionary for every row —
    /// 175,000 dictionary allocations for one refresh. Looking up an index once and
    /// subscripting the field array is the same code to read and a good deal less
    /// work to run.
    struct Columns {
        private let map: [String: Int]
        private let count: Int
        init(header: [String]) {
            var m: [String: Int] = [:]
            for (index, name) in header.enumerated() {
                m[name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))] = index
            }
            map = m
            count = header.count
        }
        /// Missing columns resolve to a sentinel that yields "" rather than trapping,
        /// so a source file gaining or losing a column cannot crash a refresh.
        subscript(name: String) -> Int { map[name] ?? -1 }
    }

    private static func forEachRow(_ data: Data, _ handle: (Columns, FieldRow) -> Void) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        var columns: Columns?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = parseCSVLine(String(line))
            guard let resolved = columns else {
                columns = Columns(header: fields)
                continue
            }
            handle(resolved, FieldRow(fields: fields))
        }
    }

    /// Bounds- and sentinel-safe field access.
    struct FieldRow {
        let fields: [String]
        subscript(index: Int) -> String {
            index >= 0 && index < fields.count ? fields[index] : ""
        }
    }

    /// RFC-4180 field splitter.
    ///
    /// Necessary rather than convenient: over 5,000 airport rows carry commas inside
    /// quoted names — "Louisville International, Standiford Field" — and splitting
    /// on commas shifts every later column on those rows, silently corrupting
    /// coordinates and elevations.
    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var pending: Character?

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { current.append("\"") }   // escaped quote
                        else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else {
                switch character {
                case "\"": inQuotes = true
                case ",":  fields.append(current); current = ""
                default:   current.append(character)
                }
            }
        }
        fields.append(current)
        return fields
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
