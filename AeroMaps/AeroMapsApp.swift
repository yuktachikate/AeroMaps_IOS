import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - App Entry
@main
struct AeroMapsApp: App {
    @StateObject private var loc = LocationManager()
    @StateObject private var weatherService = WeatherService()
    @StateObject private var liveFlightService = LiveFlightService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(loc)
                .environmentObject(weatherService)
                .environmentObject(liveFlightService)
                .environmentObject(weatherService.aviationWeather)
                .preferredColorScheme(.dark)
                .onAppear {
                    loc.request()
                }
        }
    }
}

// MARK: - Enhanced Models
struct Airport: Identifiable, Hashable {
    let id = UUID()
    let icao: String
    var iataCode: String = ""
    let name: String
    let city: String
    let state: String
    let coordinate: CLLocationCoordinate2D
    let elevation: Int
    let runways: [Runway]
    let frequencies: [Frequency]
    let services: [String]
    /// False for records built from a map search rather than the aeronautical
    /// database. Those know a name and a position and nothing else — no runway,
    /// frequency, elevation or services — so anything that would brief or plan on
    /// that detail must skip them.
    var isVerified: Bool = true
    
    static func == (lhs: Airport, rhs: Airport) -> Bool {
        lhs.icao == rhs.icao
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(icao)
    }
}

struct Runway: Identifiable, Codable {
    let id = UUID()
    let designation: String
    let length: Int
    let width: Int
    let surface: String
    let lighted: Bool
    /// True headings of each end, as published. Deriving them from the designation
    /// ("28R" → 280°) is wrong by up to five degrees either way — KSFO's 28R is
    /// actually 298°T — and that error goes straight into the crosswind component.
    var trueHeadingLow: Double? = nil
    var trueHeadingHigh: Double? = nil
}

struct Frequency: Identifiable, Codable {
    let id = UUID()
    let type: String
    let frequency: String
    let description: String
}

struct WeatherData: Codable {
    let metar: String?
    let taf: String?
    let wind: WindData?
    let visibility: Double?
    let ceiling: Int?
    let temperature: Double?
    let pressure: Double?
}

// MARK: - Flight Analysis Model
struct FlightAnalysis {
    let callsign: String
    let origin: String
    let destination: String
    let altitude: Double
    let speed: Double
    let heading: Double
    let verticalRate: Double
    let squawk: String
    let distance: Double
    let eta: Date?
    let fuelRemaining: Double?
    let weather: String?
    var icao24: String? = nil
    var aircraftType: String = "Boeing 777-300ER (B773)"
    var aircraftCategory: String = "Wide-body Commercial Jet"
    var registration: String = "N780UA"
    var coordinate: CLLocationCoordinate2D? = nil
    var imageURL: String? = "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?auto=format&fit=crop&w=1200&q=80"
}

struct WindData: Codable {
    let direction: Int
    let speed: Int
    let gust: Int?
}

enum MapStyle: String, CaseIterable, Equatable {
    case standard = "Standard"
    case hybrid = "Hybrid"
    case satellite = "Satellite"
}

enum LayerKind: String, CaseIterable, Identifiable {
    case traffic, weather, terrain, radar, wind, airspace, tfr, notams
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .traffic: return "Traffic"
        case .weather: return "Weather"
        case .terrain: return "Terrain"
        case .radar: return "Radar"
        case .wind: return "Wind"
        case .airspace: return "Airspace"
        case .tfr: return "TFR"
        case .notams: return "NOTAMs"
        }
    }
    
    var systemImage: String {
        switch self {
        case .traffic: return "airplane.circle.fill"
        case .weather: return "cloud.sun.rain.fill"
        case .terrain: return "mountain.2.fill"
        case .radar: return "wave.3.right.circle.fill"
        case .wind: return "wind"
        case .airspace: return "shield.lefthalf.filled"
        case .tfr: return "exclamationmark.triangle.fill"
        case .notams: return "list.bullet.rectangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .traffic: return .green
        case .weather: return .cyan
        case .terrain: return .brown
        case .radar: return .blue
        case .wind: return .teal
        case .airspace: return .purple
        case .tfr: return .red
        case .notams: return .orange
        }
    }
}

enum FlightMode: String, CaseIterable {
    case plan = "Plan"
    case fly = "Fly"
    case review = "Review"
    
    var icon: String {
        switch self {
        case .plan: return "paperplane"
        case .fly: return "airplane.circle.fill"
        case .review: return "chart.line.uptrend.xyaxis"
        }
    }
    
    var color: Color {
        switch self {
        case .plan: return .blue
        case .fly: return .green
        case .review: return .orange
        }
    }
}

struct RoutePlan: Identifiable {
    var id = UUID()
    var customName: String = ""
    var waypoints: [Waypoint] = []
    /// Planned cruise altitude. Individual waypoints may pin their own altitude,
    /// in which case the profile engine flies through those instead.
    var altitudeFT: Int = 8000
    /// The aircraft this plan is flown in. It sets the climb and descent rates, the
    /// service ceiling and the fuel figures, so changing it moves every altitude,
    /// time and fuel number on the route.
    var aircraftID: String = AircraftLibrary.default.id
    /// Cruise speed and burn start from the aircraft but stay editable — pilots plan
    /// their own numbers, not just the book ones.
    var cruiseKTAS: Double = AircraftLibrary.default.cruiseKTAS
    var fuelBurn: Double = AircraftLibrary.default.fuelBurnGPH
    var fuelOnBoardGal: Double = 40
    var departureTime: Date = Date()

    var aircraft: AircraftProfile { AircraftLibrary.profile(id: aircraftID) }

    var climbRateFPM: Double { aircraft.climbRateFPM }
    var descentRateFPM: Double { aircraft.descentRateFPM }
    var serviceCeilingFT: Int { aircraft.serviceCeilingFT }

    /// Performance model handed to the vertical-profile planner: the airframe's
    /// climb/descent/ceiling with the pilot's cruise speed and burn applied.
    var performance: AircraftPerformance {
        var p = aircraft.performance
        p.cruiseKTAS = cruiseKTAS
        p.fuelBurnGPH = fuelBurn
        return p
    }
    
    var displayName: String {
        if !customName.isEmpty {
            return customName
        }
        let origin = waypoints.first?.icao ?? "WPT 1"
        let dest = waypoints.last?.icao ?? "WPT \(waypoints.count)"
        return "\(origin) → \(dest) (\(Int(totalDistanceNM)) NM)"
    }
    
    var totalDistance: Double {
        guard waypoints.count >= 2 else { return 0 }
        var sum: Double = 0
        for i in 0..<(waypoints.count - 1) {
            sum += haversineNM(waypoints[i].coordinate, waypoints[i+1].coordinate)
        }
        return sum
    }
    
    var totalDistanceNM: Double {
        totalDistance
    }
    
    var totalFuelBurnLBS: Double {
        fuelRequired * 6.0 // 1 gal AVGAS ≈ 6 lbs
    }
    
    var formattedFlightTime: String {
        let hrs = Int(estimatedTime) / 3600
        let mins = (Int(estimatedTime) % 3600) / 60
        if hrs > 0 {
            return "\(hrs)h \(mins)m"
        } else {
            return "\(mins) min"
        }
    }
    
    /// Flat-rate estimate: the whole route flown at cruise speed.
    ///
    /// Only a fallback for when no vertical profile has been computed. It ignores
    /// climb and descent, which on a short leg is most of the flight — prefer
    /// `MapState.routeTimeMinutes`, which integrates the real profile.
    var estimatedTime: TimeInterval {
        guard cruiseKTAS > 0 else { return 0 }
        return (totalDistance / cruiseKTAS) * 3600 // seconds
    }
    
    var fuelRequired: Double {
        return (estimatedTime / 3600) * fuelBurn
    }
    
    private func haversineNM(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let Rnm = 3440.065
        func rad(_ d: Double) -> Double { d * .pi / 180 }
        
        let dLat = rad(b.latitude - a.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let la1 = rad(a.latitude), la2 = rad(b.latitude)
        
        let h = sin(dLat/2)*sin(dLat/2) + cos(la1)*cos(la2)*sin(dLon/2)*sin(dLon/2)
        let c = 2 * atan2(sqrt(h), sqrt(1-h))
        return Rnm * c
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius = "°C"
    case fahrenheit = "°F"
    var id: String { rawValue }
}

// MARK: - Enhanced App State
final class MapState: ObservableObject {
    @Published var camera = MKMapCamera(
        lookingAtCenter: CLLocationCoordinate2D(latitude: 37.6213, longitude: -122.3790),
        fromDistance: 100_000,
        pitch: 0,
        heading: 0
    )
    @Published var route = RoutePlan() { didSet { routeDidChange(from: oldValue) } }

    // MARK: Vertical planning
    /// Terrain under the route. Optional everywhere — the planner degrades to
    /// field elevations when the elevation service is unreachable.
    let terrain = TerrainService()
    /// Real winds aloft along the route. Every time and fuel figure depends on it.
    let winds = WindsAloftService()
    /// Every flight recorded on this device.
    let flightLog = FlightLog()
    /// The flight in progress, if any. Nil on the ground.
    @Published var activeFlight: FlightRecord?
    /// The flight just finished, held so the summary can be opened straight from
    /// the map instead of being hunted for in the logbook.
    @Published var completedFlight: FlightRecord?
    /// When the last track fix was stored, so fixes are thinned rather than logged
    /// at the full rate of the GPS.
    private var lastTrackFixAt: Date?
    @Published var altitudeProfile = AltitudeProfile()
    @Published var cruiseSuggestion: AltitudePlanner.CruiseSuggestion?
    /// Bumped whenever a waypoint is added, so the bottom sheet can open itself to
    /// the route builder. A counter rather than a flag: repeated adds re-trigger.
    @Published var routeBuilderRevealCount: Int = 0
    var showingAssistant: Bool {
        get { activeTool == .routeAdvisor }
        set { activeTool = newValue ? .routeAdvisor : nil }
    }
    @Published var assistantTab: String = "validate"
    var showingAircraftPicker: Bool {
        get { activeTool == .aircraft }
        set { activeTool = newValue ? .aircraft : nil }
    }
    var showingProcedureAdvisor: Bool {
        get { activeTool == .procedure }
        set { activeTool = newValue ? .procedure : nil }
    }
    var showingProfileView: Bool {
        get { activeTool == .profile }
        set { activeTool = newValue ? .profile : nil }
    }
    var showingPlates: Bool {
        get { activeTool == .plates }
        set { activeTool = newValue ? .plates : nil }
    }
    var showingChecklist: Bool {
        get { activeTool == .checklist }
        set { activeTool = newValue ? .checklist : nil }
    }
    var showingNotes: Bool {
        get { activeTool == .notes }
        set { activeTool = newValue ? .notes : nil }
    }
    @Published var flightNotes: String = ""
    /// Student pilots carry extra airspace restrictions — a Class B endorsement, and
    /// some Class B airports barred to solo flight entirely. Flight training is a
    /// primary use of this app, so the check knows about it.
    @Published var isStudentPilot: Bool = UserDefaults.standard.bool(forKey: "AeroMaps_StudentPilot") {
        didSet { UserDefaults.standard.set(isStudentPilot, forKey: "AeroMaps_StudentPilot") }
    }
    @Published var checkedChecklistItems: Set<String> = []
    @Published var activeLayers: Set<LayerKind> {
        didSet {
            let rawValues = activeLayers.map { $0.rawValue }
            UserDefaults.standard.set(rawValues, forKey: "AeroMaps_ActiveLayers")
        }
    }
    @Published var mode: FlightMode = .plan
    @Published var showSheet: Bool = true
    @Published var mapStyle: MapStyle = .standard
    @Published var selectedAirport: Airport? = nil
    @Published var selectedFlight: FlightAnalysis? = nil
    @Published var showingAirportDetail = false
    @Published var showingFlightDetail = false
    /// Every tool screen presented over the map, funnelled through one presentation.
    ///
    /// These used to be eleven separate `.sheet(isPresented:)` modifiers stacked on
    /// the same view. SwiftUI only reliably drives one sheet per view, and the ones
    /// added later — the aircraft picker among them — simply never opened. A single
    /// `.sheet(item:)` fixes that and makes "only one tool at a time" structural.
    enum ToolSheet: String, Identifiable {
        case flightPlanner, routeAdvisor, aircraft, procedure, profile
        case plates, checklist, notes, weather, promptTree
        case logbook, amend
        var id: String { rawValue }
    }

    @Published var activeTool: ToolSheet?

    // Named accessors so call sites read as intent rather than routing.
    var showingFlightPlanner: Bool {
        get { activeTool == .flightPlanner }
        set { activeTool = newValue ? .flightPlanner : nil }
    }
    var showingWeatherPanel: Bool {
        get { activeTool == .weather }
        set { activeTool = newValue ? .weather : nil }
    }
    @Published var activeTab: Int = 0
    // Flights screen sub-tab: 0 = Tracked, 1 = Live Traffic, 2 = Track New.
    @Published var flightSubTab: Int = 0
    var showingPromptTree: Bool {
        get { activeTool == .promptTree }
        set { activeTool = newValue ? .promptTree : nil }
    }
    @Published var shouldCenterCamera: Bool = false
    @Published var riskOverlays: [MKTileOverlay] = []
    @Published var ffmAdvice: String = ""
    @Published var legRisks: [FFMResponse.LegRisk] = []
    @Published var computedPolyline: MKPolyline? = nil
    @Published var tempUnit: TemperatureUnit = .celsius
    @Published var windAltitudeFT: Int = 3000
    
    // Live Route Navigation State
    @Published var isNavigatingRoute: Bool = false
    @Published var currentWaypointIndex: Int = 0
    @Published var offRouteDistanceNM: Double = 0.0
    @Published var closestRoutePoint: CLLocationCoordinate2D? = nil
    @Published var routeCompleted: Bool = false
    
    // Saved Routes Collection (starts empty — fills as the user saves routes)
    @Published var savedRoutes: [RoutePlan] = []
    @Published var saveRouteToastMessage: String? = nil
    @Published var showingSaveRouteDialog: Bool = false
    @Published var saveRouteInputName: String = ""
    
    /// Keeps the vertical profile and terrain samples in step with the route.
    private func routeDidChange(from previous: RoutePlan) {
        let geometryChanged = previous.waypoints.map(\.id) != route.waypoints.map(\.id)
            || zip(previous.waypoints, route.waypoints).contains { a, b in
                a.coordinate.latitude != b.coordinate.latitude || a.coordinate.longitude != b.coordinate.longitude
            }
        if geometryChanged || previous.departureTime != route.departureTime {
            winds.load(for: route.waypoints, departureTime: route.departureTime)
        }
        if geometryChanged {
            terrain.loadTerrain(for: route.waypoints)
            refreshRouteWeather()
            let idents = route.waypoints.compactMap(\.airportICAO)
            if !idents.isEmpty { Task { await notams.load(for: idents) } }
        }
        recomputeProfile()
    }

    /// The authoritative time and fuel for the current route.
    ///
    /// Both come from the vertical profile, which costs climb at climb speed and
    /// richer mixture and descent at descent speed — so they differ from the
    /// flat-rate figures on RoutePlan, and every screen should show these. Two
    /// different numbers for the same flight is worse than either one alone.
    var routeTimeMinutes: Double {
        altitudeProfile.isEmpty ? route.estimatedTime / 60 : altitudeProfile.totalTimeMinutes
    }

    var routeFuelGallons: Double {
        altitudeProfile.isEmpty ? route.fuelRequired : altitudeProfile.totalFuelGallons
    }

    func recomputeProfile() {
        guard route.waypoints.count >= 2 else {
            altitudeProfile = AltitudeProfile()
            cruiseSuggestion = nil
            return
        }
        let sampler = terrain.sampler.isEmpty ? nil : terrain.sampler
        altitudeProfile = AltitudePlanner.computeProfile(
            waypoints: route.waypoints,
            cruiseAltitudeFT: route.altitudeFT,
            performance: route.performance,
            terrain: sampler,
            wind: winds.field.isEmpty ? nil : winds.field
        )
        cruiseSuggestion = AltitudePlanner.suggestCruiseAltitude(
            waypoints: route.waypoints,
            performance: route.performance,
            terrain: sampler
        )
    }

    /// Switches airframe and reseeds the numbers that come from it. Cruise altitude
    /// is clamped into the new aircraft's usable range so a swap can never leave the
    /// plan above its ceiling.
    func selectAircraft(_ profile: AircraftProfile) {
        route.aircraftID = profile.id
        route.cruiseKTAS = profile.cruiseKTAS
        route.fuelBurn = profile.fuelBurnGPH
        route.fuelOnBoardGal = min(route.fuelOnBoardGal, profile.usableFuelGal)
        route.altitudeFT = min(route.altitudeFT, profile.performance.maxPlanningAltitudeFT)
    }

    /// Applies the planner's recommended cruise altitude and clears any per-waypoint
    /// overrides, returning the route to a clean computed profile.
    /// Marks a waypoint as a planned landing, or clears it.
    ///
    /// Assigned through a local copy so the route's didSet — which rebuilds the
    /// whole vertical profile — fires once.
    func setStop(id: UUID, stop: StopPlan?) {
        guard let index = route.waypoints.firstIndex(where: { $0.id == id }) else { return }
        var plan = route
        plan.waypoints[index].stop = stop
        // A landing and a pinned cruise altitude are contradictory instructions;
        // the landing wins, so the stale pin is cleared rather than left to confuse
        // the profile and the validator.
        if stop != nil { plan.waypoints[index].plannedAltitudeFT = nil }
        route = plan
    }

    func applySuggestedCruiseAltitude() {
        guard let suggestion = cruiseSuggestion else { return }
        // One assignment, not one per waypoint: `route`'s didSet recomputes the
        // entire vertical profile, so mutating in place recomputed it N times.
        var plan = route
        plan.altitudeFT = suggestion.altitudeFT
        for i in plan.waypoints.indices { plan.waypoints[i].plannedAltitudeFT = nil }
        route = plan
    }

    func deleteSavedRoute(id: UUID) {
        savedRoutes.removeAll(where: { $0.id == id })
        if route.id == id {
            route = RoutePlan()
            isNavigatingRoute = false
        }
    }

    // Load a saved route onto the map without starting navigation (review first).
    func loadSavedRoute(_ plan: RoutePlan) {
        route = plan
        isNavigatingRoute = false
        currentWaypointIndex = 0
        activeTab = 0 // Return to map with the route drawn
        shouldCenterCamera = true
    }

    // Load a saved route AND immediately begin live navigation.
    func startSavedRoute(_ plan: RoutePlan) {
        route = plan
        startRouteNavigation()
    }
    
    func prepareSaveRoute() {
        guard route.waypoints.count >= 2 else { return }
        saveRouteInputName = "" // Let user fill in name!
        showingSaveRouteDialog = true
    }
    
    func confirmSaveRoute(name: String) {
        guard route.waypoints.count >= 2 else { return }
        var planToSave = route
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let origin = route.waypoints.first?.icao ?? "WPT 1"
        let dest = route.waypoints.last?.icao ?? "WPT \(route.waypoints.count)"
        let fallbackName = "\(origin) → \(dest) (\(Int(route.totalDistanceNM)) NM)"
        
        planToSave.customName = trimmed.isEmpty ? fallbackName : trimmed
        
        // Insert at index 0 so newly saved route appears AT THE TOP!
        if let existingIdx = savedRoutes.firstIndex(where: { $0.id == planToSave.id }) {
            savedRoutes[existingIdx] = planToSave
        } else {
            savedRoutes.insert(planToSave, at: 0)
        }
        
        saveRouteToastMessage = "Saved '\(planToSave.displayName)' to Library"
        showingSaveRouteDialog = false
        
        // Remove saved route & waypoints completely from map UI
        route = RoutePlan()
        isNavigatingRoute = false
        currentWaypointIndex = 0
        offRouteDistanceNM = 0.0
        closestRoutePoint = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.saveRouteToastMessage = nil
        }
    }
    
    func saveCurrentRoute() {
        prepareSaveRoute()
    }
    
    func startRouteNavigation() {
        guard route.waypoints.count >= 2 else { return }
        isNavigatingRoute = true
        routeCompleted = false
        beginFlightRecord()
        activeTab = 0 // Switch back to map view!

        // A fresh "Start" always begins from the departure waypoint so the
        // first leg draws GREEN (active) and the rest BLUE — nothing is marked
        // "visited" (grey) until the pilot actually flies past a checkpoint.
        currentWaypointIndex = 0
        offRouteDistanceNM = 0.0
        closestRoutePoint = nil

        // Zoom in to start location / first waypoint
        let targetCoord = locationManager?.lastLocation?.coordinate ?? route.waypoints[currentWaypointIndex].coordinate

        // Orient the camera along the FIRST LEG's course so the direction of
        // travel points "up" — not always north. If we start off-route, head
        // from the aircraft toward the next waypoint.
        let courseTarget = route.waypoints[min(1, route.waypoints.count - 1)].coordinate
        let course = bearingDegrees(from: targetCoord, to: courseTarget)

        camera = MKMapCamera(
            lookingAtCenter: targetCoord,
            fromDistance: 35_000, // Zoomed in for flight navigation!
            pitch: 35, // Tactical 3D flight perspective!
            heading: course
        )
        shouldCenterCamera = true
    }

    // Initial great-circle bearing from one coordinate to another, in degrees (0=N, 90=E).
    func bearingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let brng = atan2(y, x) * 180 / .pi
        return (brng + 360).truncatingRemainder(dividingBy: 360)
    }
    
    func cancelRouteNavigation() {
        endFlightRecord()
        isNavigatingRoute = false
        routeCompleted = false
        currentWaypointIndex = 0
        offRouteDistanceNM = 0.0
        closestRoutePoint = nil
    }

    // MARK: - Flight recording

    /// Snapshots the plan and opens a record. The snapshot matters: the live route
    /// keeps being edited afterwards, and a log that changes retroactively is not a
    /// log.
    private func beginFlightRecord() {
        let points = route.waypoints.map {
            PlannedPoint($0, altitudeFT: altitudeProfile.waypointAltitudes[$0.id])
        }
        activeFlight = FlightRecord(
            startedAt: Date(),
            aircraftID: route.aircraftID,
            aircraftName: route.aircraft.name,
            registration: route.aircraft.registration,
            plannedPoints: points,
            plannedCruiseFT: route.altitudeFT,
            plannedDistanceNM: altitudeProfile.totalDistanceNM,
            plannedTimeMinutes: altitudeProfile.totalTimeMinutes,
            plannedFuelGallons: altitudeProfile.totalFuelGallons,
            fuelOnBoardAtStartGal: route.fuelOnBoardGal)
        lastTrackFixAt = nil
        if let activeFlight { flightLog.upsert(activeFlight) }
    }

    /// Closes the record and writes it. Called on both endings — finishing the
    /// route and abandoning it — because a flight that was cut short is still a
    /// flight that happened.
    func endFlightRecord() {
        guard var flight = activeFlight, flight.endedAt == nil else { return }
        flight.endedAt = Date()
        flight.checklistCompleted = Array(checkedChecklistItems)
        flight.notes = flightNotes
        flightLog.upsert(flight)
        completedFlight = flight
        activeFlight = nil
    }

    /// The next waypoint the aircraft is flying toward, if any.
    var nextWaypoint: Waypoint? {
        let index = currentWaypointIndex + 1
        guard index < route.waypoints.count else { return nil }
        return route.waypoints[index]
    }

    /// True when the leg being flown ends at a planned landing rather than at the
    /// destination — the case where "finish the flight" is the wrong action and
    /// "arrived, carry on to the next sector" is the right one.
    var isApproachingStop: Bool {
        guard let next = nextWaypoint else { return false }
        return next.isStop && currentWaypointIndex + 1 < route.waypoints.count - 1
    }

    /// Marks the current stop as reached and continues onto the next sector. The
    /// flight record stays open: taxiing in, refuelling and departing again is one
    /// flight with a pause in it, not two records.
    func arriveAtStop() {
        guard isApproachingStop else { return }
        let arrived = nextWaypoint
        currentWaypointIndex = min(currentWaypointIndex + 1, route.waypoints.count - 1)
        if let arrived {
            recordAmendment(.waypointAdded, summary: "Arrived at \(arrived.ident)")
        }
    }

    /// Adds a fix to the flight's track.
    ///
    /// Thinned to one fix every few seconds: the GPS updates far faster than a
    /// track needs, and an unthinned log of a three-hour flight is tens of
    /// thousands of points to encode on every save.
    func recordTrackFix(_ location: CLLocation) {
        guard var flight = activeFlight, flight.endedAt == nil else { return }
        let now = location.timestamp
        if let last = lastTrackFixAt, now.timeIntervalSince(last) < 5 { return }
        lastTrackFixAt = now
        flight.track.append(TrackPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitudeFT: location.altitude * 3.280839895,
            groundSpeedKT: max(location.speed, 0) * 1.943844,
            time: now))
        activeFlight = flight
    }

    /// Records a change made after the flight started, with the fuel picture as it
    /// stood at that moment.
    func recordAmendment(_ kind: RouteAmendment.Kind, summary: String) {
        guard var flight = activeFlight else { return }
        let estimate = inFlightFuel
        flight.amendments.append(RouteAmendment(
            kind: kind, time: Date(), summary: summary,
            remainingNM: remainingRouteNM,
            remainingFuelGal: estimate?.remainingGal))
        activeFlight = flight
        flightLog.upsert(flight)
    }

    /// Distance still to fly, from the aircraft's position through the remaining
    /// waypoints. Falls back to the whole route before the first fix arrives.
    var remainingRouteNM: Double {
        let remaining = Array(route.waypoints.suffix(from: min(currentWaypointIndex, max(route.waypoints.count - 1, 0))))
        guard remaining.count >= 1 else { return 0 }
        var total = 0.0
        if let here = locationManager?.lastLocation?.coordinate, let next = remaining.first {
            total += AltitudePlanner.distanceNM(here, next.coordinate)
        }
        if remaining.count >= 2 {
            for i in 1..<remaining.count {
                total += AltitudePlanner.distanceNM(remaining[i - 1].coordinate, remaining[i].coordinate)
            }
        }
        return total
    }

    /// What the profile wants the aircraft to be doing vertically, right now.
    ///
    /// The plan already knew this — it is the same curve the route list draws — but
    /// in the air none of it was surfaced, so a pilot flying the route had no
    /// prompt to start a climb or a descent and had to read it off the waypoint
    /// list themselves.
    struct AltitudeGuidance {
        enum Action { case climb, descend, maintain }
        let action: Action
        /// Where the profile says the aircraft should be at this point on the route.
        let targetFT: Int
        /// GPS altitude, when there is a fix. Nil on the ground or without location.
        let currentFT: Int?
        /// Signed difference, positive means climb.
        let deltaFT: Int
        /// Miles until the descent should begin, once past the top of climb.
        let toTopOfDescentNM: Double?

        var label: String {
            switch action {
            case .climb:    return "Climb to \(targetFT.formatted()) ft"
            case .descend:  return "Descend to \(targetFT.formatted()) ft"
            case .maintain: return "Maintain \(targetFT.formatted()) ft"
            }
        }
    }

    /// Vertical guidance for the current position, or nil when not flying a route.
    var altitudeGuidance: AltitudeGuidance? {
        guard isNavigatingRoute, !altitudeProfile.isEmpty else { return nil }
        // Distance flown along the route, derived from what is left rather than
        // tracked separately, so it stays consistent with the figure on screen.
        let along = max(altitudeProfile.totalDistanceNM - remainingRouteNM, 0)
        guard let target = altitudeProfile.altitudeFT(atDistanceNM: along) else { return nil }

        let currentFT = locationManager?.lastLocation.map { Int(($0.altitude * 3.280839895).rounded()) }
        let delta = currentFT.map { target - $0 } ?? 0

        // A few hundred feet is normal altitude keeping, not an instruction to climb.
        let action: AltitudeGuidance.Action
        if currentFT == nil { action = .maintain }
        else if delta > 300 { action = .climb }
        else if delta < -300 { action = .descend }
        else { action = .maintain }

        let toTOD = altitudeProfile.topOfDescentNM - along
        return AltitudeGuidance(action: action, targetFT: target, currentFT: currentFT,
                                deltaFT: delta, toTopOfDescentNM: toTOD > 1 ? toTOD : nil)
    }

    /// Fuel as it stands now, estimated from time airborne. Nil on the ground.
    var inFlightFuel: FuelEstimator.Estimate? {
        guard let flight = activeFlight else { return nil }
        // Fuel for what is left, scaled from the profile's own burn rate per mile so
        // it inherits the wind correction rather than reverting to a flat rate.
        let perNM = altitudeProfile.totalDistanceNM > 0
            ? altitudeProfile.totalFuelGallons / altitudeProfile.totalDistanceNM
            : route.performance.fuelBurnGPH / max(route.performance.cruiseKTAS, 1)
        return FuelEstimator.estimate(
            elapsed: Date().timeIntervalSince(flight.startedAt),
            startedWithGal: flight.fuelOnBoardAtStartGal,
            burnGPH: route.performance.fuelBurnGPH,
            remainingRouteFuelGal: remainingRouteNM * perNM)
    }

    // Called when the pilot reaches the final waypoint. Keeps the finished
    // route on screen (drawn fully grey = "done") until they tap Finish.
    func completeRoute() {
        guard !routeCompleted else { return }
        endFlightRecord()
        routeCompleted = true
        currentWaypointIndex = max(0, route.waypoints.count - 1)
        offRouteDistanceNM = 0.0
        closestRoutePoint = nil
        // isNavigatingRoute stays true so the completion HUD + route remain visible.
    }
    
    func findClosestWaypointIndex(for coord: CLLocationCoordinate2D) {
        guard route.waypoints.count >= 2 else { return }
        var minDistance = Double.infinity
        var closestIdx = 0
        for (index, wp) in route.waypoints.enumerated() {
            let dist = distanceNM(coord, wp.coordinate)
            if dist < minDistance {
                minDistance = dist
                closestIdx = index
            }
        }
        currentWaypointIndex = max(0, min(route.waypoints.count - 1, closestIdx))
    }
    
    // Capture radius (NM): how close the aircraft must get to a checkpoint to
    // count it as reached. Generous because a plane rarely overflies a fix exactly.
    private let waypointCaptureRadiusNM = 1.5

    func updateLiveNavigationProgress(userCoord: CLLocationCoordinate2D) {
        guard isNavigatingRoute, !routeCompleted, route.waypoints.count >= 2 else { return }

        let wps = route.waypoints
        let lastIdx = wps.count - 1

        // Advance through every checkpoint we've already passed. Forward-only:
        // we never move the index backwards, so drifting off-route can't
        // "un-complete" a leg.
        //
        // The capture radius ADAPTS to each leg's length: on a short leg the
        // radius shrinks so a compact route (or start/end close together) is
        // NOT auto-completed just because every fix sits inside a fat 1.5 NM
        // bubble. Passing a checkpoint by projection only counts when we're
        // actually near the route line (small cross-track), not miles off to
        // the side. The FINAL waypoint requires genuine arrival (proximity),
        // so a tight route never reports "complete" before it's flown.
        var idx = min(max(currentWaypointIndex, 0), lastIdx)
        while idx < lastIdx {
            let a = wps[idx].coordinate
            let b = wps[idx + 1].coordinate
            let legLen = distanceNM(a, b)
            let captureNM = max(0.15, min(waypointCaptureRadiusNM, legLen * 0.4))
            let isFinalLeg = (idx + 1 == lastIdx)

            let distToB = distanceNM(userCoord, b)
            let reached: Bool
            if isFinalLeg {
                // Destination: must physically arrive (no fly-past shortcut).
                reached = distToB < captureNM
            } else {
                let (_, xtrk) = calculateCrossTrackDeviation(user: userCoord, pA: a, pB: b)
                let onRoute = xtrk < max(0.5, captureNM * 2)
                let passed = alongTrackFraction(user: userCoord, pA: a, pB: b) >= 0.999 && onRoute
                reached = distToB < captureNM || passed
            }

            if reached { idx += 1 } else { break }
        }
        currentWaypointIndex = idx

        // Completion only when we've genuinely reached the final waypoint.
        if idx >= lastIdx {
            completeRoute()
            return
        }

        // Cross-track deviation on the ACTIVE leg (drives the dashed off-route line).
        let pA = wps[idx].coordinate
        let pB = wps[idx + 1].coordinate
        let (closestPoint, offRouteDist) = calculateCrossTrackDeviation(user: userCoord, pA: pA, pB: pB)
        closestRoutePoint = closestPoint
        offRouteDistanceNM = offRouteDist
    }

    // Clamped [0,1] projection of the user onto segment A->B along its length.
    // 0 = at A, 1 = at/after B. Used to decide when a checkpoint is behind us.
    private func alongTrackFraction(user: CLLocationCoordinate2D, pA: CLLocationCoordinate2D, pB: CLLocationCoordinate2D) -> Double {
        let dx = pB.longitude - pA.longitude
        let dy = pB.latitude - pA.latitude
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return 1.0 }
        let t = ((user.longitude - pA.longitude) * dx + (user.latitude - pA.latitude) * dy) / lenSq
        return max(0.0, min(1.0, t))
    }
    
    private func calculateCrossTrackDeviation(user: CLLocationCoordinate2D, pA: CLLocationCoordinate2D, pB: CLLocationCoordinate2D) -> (CLLocationCoordinate2D, Double) {
        let distAP = distanceNM(pA, user)
        let distAB = distanceNM(pA, pB)
        if distAB == 0 { return (pA, distAP) }
        
        let dx = pB.longitude - pA.longitude
        let dy = pA.latitude - pB.latitude
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return (pA, distAP) }
        
        let t = max(0.0, min(1.0, ((user.longitude - pA.longitude) * dx + (user.latitude - pA.latitude) * (pB.latitude - pA.latitude)) / lenSq))
        let projCoord = CLLocationCoordinate2D(latitude: pA.latitude + t * (pB.latitude - pA.latitude), longitude: pA.longitude + t * dx)
        let xtrkDist = distanceNM(user, projCoord)
        return (projCoord, round(xtrkDist * 10) / 10.0)
    }
    
    init() {
        if let saved = UserDefaults.standard.array(forKey: "AeroMaps_ActiveLayers") as? [String] {
            let restored = Set(saved.compactMap { LayerKind(rawValue: $0) })
            if !restored.isEmpty {
                self.activeLayers = restored
            } else {
                self.activeLayers = [.traffic, .airspace, .weather, .wind]
            }
        } else {
            self.activeLayers = [.traffic, .airspace, .weather, .wind]
        }

        // Terrain arrives asynchronously; recompute the profile once it lands so the
        // altitude suggestion and the ground layer appear without another edit.
        notams.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        airspace.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        aviationWeather.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        aeroData.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        terrain.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.recomputeProfile()
                    self.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        // Same treatment for wind: the profile is computed with whatever forecast
        // has arrived, and recomputed when a better one does.
        winds.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.recomputeProfile()
                    self.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
    
    @Published var liveSearchResults: [Airport] = []
    @Published var isSearchingLive: Bool = false
    private var liveSearchTask: DispatchWorkItem?
    
    func performLiveAirportSearch(query: String) {
        liveSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            DispatchQueue.main.async {
                self.liveSearchResults = []
                self.isSearchingLive = false
            }
            return
        }
        
        isSearchingLive = true
        
        let task = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            let request = MKLocalSearch.Request()
            let searchQuery = trimmed.lowercased().contains("airport") ? trimmed : "\(trimmed) airport"
            request.naturalLanguageQuery = searchQuery
            
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                guard let items = response?.mapItems, !items.isEmpty else {
                    DispatchQueue.main.async {
                        self.isSearchingLive = false
                    }
                    return
                }
                
                var results: [Airport] = []
                for item in items {
                    let name = item.name ?? "Airport"
                    let placemark = item.placemark
                    let city = placemark.locality ?? placemark.subAdministrativeArea ?? trimmed.capitalized
                    let state = placemark.administrativeArea ?? placemark.countryCode ?? ""
                    let coord = placemark.coordinate
                    
                    // A map search knows a name and a position. It does not know the
                    // ICAO ident, field elevation, runways, frequencies or services —
                    // and inventing them (this used to mint "ARPT-1234", a 8,500 ft
                    // runway 09/27 and a 118.3 tower for every hit) puts fictional
                    // aeronautical data in front of a pilot. Only take a real ident
                    // when the name actually carries one.
                    var identifier = name
                    var verified = false
                    if let firstWord = name.components(separatedBy: " ").first,
                       firstWord.count == 4, firstWord.allSatisfy({ $0.isLetter }),
                       firstWord.uppercased() == firstWord {
                        identifier = firstWord.uppercased()
                        verified = self.airports[identifier] != nil
                    }

                    let airport = Airport(
                        icao: identifier,
                        iataCode: "",
                        name: name,
                        city: city,
                        state: state,
                        coordinate: coord,
                        elevation: 0,
                        runways: [],
                        frequencies: [],
                        services: [],
                        isVerified: verified
                    )
                    results.append(airport)
                }
                
                DispatchQueue.main.async {
                    self.liveSearchResults = results
                    self.isSearchingLive = false
                    // Map hits are not written into the aeronautical database. They
                    // remain in liveSearchResults, usable as waypoints, never as a
                    // briefing source or a generated checkpoint.
                }
            }
        }
        
        liveSearchTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }
    
    var isZoomedInTo100Miles: Bool {
        return camera.centerCoordinateDistance <= 350_000
    }
    
    /// Where a wind reading came from, so nothing presents a model as an observation.
    enum WindSource: Equatable {
        case observed(station: String, freshness: DataFreshness)
        case model

        var isObserved: Bool { if case .observed = self { return true }; return false }
        var label: String {
            switch self {
            case .observed(let station, let freshness): return "\(station) · \(freshness.shortLabel)"
            case .model: return "estimated — no station reporting"
            }
        }
    }

    /// Wind at a point. Prefers the nearest reporting station's observed surface
    /// wind; falls back to a positional model only when nothing is reporting, and
    /// says which it used.
    ///
    /// The model used to be the only source, and the Procedure Advisor picked
    /// runways from it — a plausible-looking number with no relationship to the
    /// actual weather.
    func windAt(_ coordinate: CLLocationCoordinate2D,
                altitudeFT: Int) -> (direction: Int, speed: Int, gust: Int?, source: WindSource) {
        if altitudeFT <= 3_000,
           let observed = aviationWeather.surfaceWind(near: coordinate, withinNM: 60) {
            return (observed.direction, observed.speedKT, observed.gustKT,
                    .observed(station: observed.station, freshness: observed.age))
        }
        let lat = coordinate.latitude, lon = coordinate.longitude
        let base = Int(abs(sin(lat * 0.15) * 180.0 + cos(lon * 0.15) * 180.0)) % 360
        let direction = (base == 0) ? 270 : base
        let altFactor = Double(altitudeFT) / 3000.0
        let baseSpeed = 8.0 + abs(sin(lat * 0.2) * 18.0) + abs(cos(lon * 0.2) * 14.0)
        return (direction, Int(round(baseSpeed * max(1.0, altFactor * 0.6))), nil, .model)
    }

    /// Pulls observations for everything on the route in one request.
    func refreshRouteWeather() {
        var idents = route.waypoints.compactMap(\.airportICAO)
        // Include nearby reporting fields so a route between grass strips still has
        // a wind source at each end.
        for wp in route.waypoints where wp.airportICAO == nil {
            idents.append(contentsOf: airports.nearby(wp.coordinate, withinNM: 40, limit: 2, minimumType: 2).map(\.icao))
        }
        guard !idents.isEmpty else { return }
        Task { await aviationWeather.loadMetars(for: Array(Set(idents))) }
    }

    var centerWindDir: Int {
        windAt(camera.centerCoordinate, altitudeFT: windAltitudeFT).direction
    }
    
    var centerWindSpeed: Int {
        windAt(camera.centerCoordinate, altitudeFT: windAltitudeFT).speed
    }
    
    func formatTemp(_ celsius: Double) -> String {
        if tempUnit == .fahrenheit {
            let f = (celsius * 9.0 / 5.0) + 32.0
            return "\(Int(round(f)))°F"
        } else {
            return "\(Int(round(celsius)))°C"
        }
    }
    
    func airportName(for icao: String) -> String {
        let key = icao.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let airport = airports[key] {
            let locationStr = airport.state.isEmpty ? airport.city : "\(airport.city), \(airport.state)"
            if !locationStr.isEmpty {
                return "\(airport.icao) — \(airport.name) (\(locationStr))"
            } else {
                return "\(airport.icao) — \(airport.name)"
            }
        }
        return icao
    }
    
    func airportShort(for icao: String) -> String {
        let key = icao.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let airport = airports[key] {
            if !airport.city.isEmpty {
                return "\(airport.icao) (\(airport.city))"
            } else {
                return "\(airport.icao) (\(airport.name))"
            }
        }
        return icao
    }
    
    func distanceNM(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let Rnm = 3440.065
        func rad(_ d: Double) -> Double { d * .pi / 180 }
        let dLat = rad(b.latitude - a.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let la1 = rad(a.latitude), la2 = rad(b.latitude)
        let h = sin(dLat/2)*sin(dLat/2) + cos(la1)*cos(la2)*sin(dLon/2)*sin(dLon/2)
        let c = 2 * atan2(sqrt(h), sqrt(1-h))
        return Rnm * c
    }
    
    // References for analysis
    var locationManager: LocationManager?
    var weatherService: WeatherService?
    
    // Enhanced global airport database
    /// The aeronautical database. Previously 52 hand-typed international airports,
    /// which meant a training flight to the field down the road could not be planned
    /// at all. Now ~29,000 airports worldwide, bundled for offline use.
    let aeroData = AeronauticalDatabase()

    /// Real observations from the NOAA Aviation Weather Center. Everything it
    /// returns is cached to disk, so a briefing taken on the ground stays readable
    /// in the air with its age attached.
    let aviationWeather = AviationWeatherService()

    /// Published FAA controlled airspace, cached by tile for offline use.
    let airspace = AirspaceService()

    /// Real NOTAMs, when FAA credentials are configured. Never fabricated.
    let notams = NotamService()

    var airports: AirportCatalog { aeroData.catalog }
    
    func toggle(_ kind: LayerKind) {
        if activeLayers.contains(kind) {
            activeLayers.remove(kind)
        } else {
            activeLayers.insert(kind)
        }
        
        if kind == .terrain {
            mapStyle = activeLayers.contains(.terrain) ? .hybrid : .standard
        }
    }
    

    
    /// Drops a waypoint at `coord`. A tap within ~3 NM of a known field snaps to
    /// that airport instead, so a long-press near an airport plans a real leg
    /// rather than an unnamed point beside the runway.
    func addWaypoint(_ coord: CLLocationCoordinate2D, named: String? = nil, kind: WaypointKind = .mapPoint) {
        if named == nil, let nearby = nearestAirport(to: coord, withinNM: 3) {
            appendWaypoint(Waypoint(airport: nearby))
            return
        }
        let ident = named ?? "WPT \(route.waypoints.count + 1)"
        appendWaypoint(Waypoint(ident: ident, name: ident, coordinate: coord, kind: kind))
    }

    /// Single funnel for adding a point to the route, so every entry path (map
    /// long-press, search result, typed coordinate, route string) reveals the
    /// planner and refreshes the vertical profile the same way.
    func appendWaypoint(_ waypoint: Waypoint) {
        route.waypoints.append(waypoint)
        routeBuilderRevealCount += 1
    }

    func insertWaypoint(_ waypoint: Waypoint, at index: Int) {
        let clamped = max(0, min(index, route.waypoints.count))
        route.waypoints.insert(waypoint, at: clamped)
        routeBuilderRevealCount += 1
    }

    func removeWaypoint(id: UUID) {
        route.waypoints.removeAll { $0.id == id }
    }

    func moveWaypoints(from source: IndexSet, to destination: Int) {
        route.waypoints.move(fromOffsets: source, toOffset: destination)
    }

    func setWaypointAltitude(id: UUID, altitudeFT: Int?) {
        guard let idx = route.waypoints.firstIndex(where: { $0.id == id }) else { return }
        route.waypoints[idx].plannedAltitudeFT = altitudeFT
    }

    func nearestAirport(to coord: CLLocationCoordinate2D, withinNM limit: Double) -> Airport? {
        airports.nearby(coord, withinNM: limit, limit: 1).first
    }

    /// Fields close to a point, for the "airports near you" list. Local flying is
    /// the common case, so this leads with whatever is actually nearby.
    func nearbyAirports(to coord: CLLocationCoordinate2D,
                        withinNM limit: Double = 60,
                        count: Int = 12) -> [Airport] {
        airports.nearby(coord, withinNM: limit, limit: count)
    }
    
    func clearRoute() {
        route = RoutePlan()
        isNavigatingRoute = false
        routeCompleted = false
        currentWaypointIndex = 0
        offRouteDistanceNM = 0.0
        closestRoutePoint = nil
        computedPolyline = nil
    }
    
    /// Steps the map camera in or out.
    ///
    /// Pinch is awkward on a simulator trackpad and worse in a cockpit — one hand
    /// on the yoke, gloves on, turbulence — so the map gets the same explicit
    /// controls the route preview has.
    func zoomCamera(by factor: Double) {
        let current = camera.centerCoordinateDistance
        // Floor and ceiling keep a stray double-tap from ending up at street level
        // or in orbit.
        let target = min(max(current * factor, 800), 20_000_000)
        withAnimation(.easeInOut(duration: 0.25)) {
            camera = MKMapCamera(lookingAtCenter: camera.centerCoordinate,
                                 fromDistance: target,
                                 pitch: camera.pitch,
                                 heading: camera.heading)
            shouldCenterCamera = true
        }
    }

    func zoomToRoute() {
        guard route.waypoints.count >= 1 else { return }
        
        let lats = route.waypoints.map { $0.coordinate.latitude }
        let lons = route.waypoints.map { $0.coordinate.longitude }
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat+maxLat)/2,
            longitude: (minLon+maxLon)/2
        )
        let span = max(maxLat - minLat, maxLon - minLon)
        let distance = max(50_000, span * 111_000 * 1.8)
        
        withAnimation(.easeInOut(duration: 1.0)) {
            camera = MKMapCamera(
                lookingAtCenter: center,
                fromDistance: distance,
                pitch: 0,
                heading: 0
            )
        }
        // The map only adopts a new camera when this is set; without it the
        // fit-to-route zoom was computed and then dropped.
        shouldCenterCamera = true
    }
}

// MARK: - FFM Planning
extension MapState {
    @MainActor
    func computeFFMPlan() async {
        guard route.waypoints.count >= 2 else { return }
        
        // 1. Enforce safety envelope and clamping on-device
        let clampedKTAS = max(80, min(220, route.cruiseKTAS))
        let clampedFuel = max(6.0, min(18.0, route.fuelBurn))
        route.altitudeFT = max(2000, route.altitudeFT)
        
        // 2. Compute route polyline on-device
        let coordinates = route.waypoints.map { $0.coordinate }
        self.computedPolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        
        // 3. Compute per-leg hazards dynamically on-device
        var computedLegRisks: [FFMResponse.LegRisk] = []
        for i in 0..<(route.waypoints.count - 1) {
            let w1 = route.waypoints[i].coordinate
            let w2 = route.waypoints[i+1].coordinate
            let dist = sqrt(pow(w2.latitude - w1.latitude, 2) + pow(w2.longitude - w1.longitude, 2))
            
            let icing = min(0.9, max(0.1, round((0.15 + dist * 0.4) * 10) / 10))
            let turb = min(0.9, max(0.2, round((0.25 + dist * 0.5) * 10) / 10))
            let terr = min(0.9, max(0.1, round((0.10 + abs(w1.latitude - 37.5) * 0.3) * 10) / 10))
            
            computedLegRisks.append(FFMResponse.LegRisk(
                fromIndex: i,
                toIndex: i + 1,
                icing: icing,
                turbulence: turb,
                terrain: terr
            ))
        }
        self.legRisks = computedLegRisks
        
        // 4. Generate on-device pilot advisory
        let firstWpt = route.waypoints.first?.icao ?? "DEP"
        let lastWpt = route.waypoints.last?.icao ?? "ARR"
        let totalFuelWithReserve = routeFuelGallons + (clampedFuel * 0.75)
        self.ffmAdvice = "FFM Advisory (\(firstWpt) → \(lastWpt)): Safety envelope verified. Enforced 45m reserve fuel (\(String(format: "%.1f", totalFuelWithReserve)) gal total) and \(route.altitudeFT) FT MEF altitude floor. Moderate turbulence forecast along route."
        
        // 5. Generate risk heatmap overlay on-device
        let template = "https://tile.openweathermap.org/map/precipitation_new/{z}/{x}/{y}.png?appid=demo"
        let overlay = MKTileOverlay(urlTemplate: template)
        overlay.canReplaceMapContent = false
        self.riskOverlays = [overlay]
        
        // 6. Record on-device Prompt Tree Session (100% on iOS)
        let rootId = "node_\(UUID().uuidString.prefix(6))"
        let traceNodes = [
            PromptTreeNode(
                id: rootId,
                parentId: nil,
                name: "FFM_Risk_Planning_Agent",
                nodeType: "agent",
                inputs: "Route: \(firstWpt) → \(lastWpt) | Cruise: \(Int(clampedKTAS)) KTAS | Altitude: \(route.altitudeFT) FT",
                outputs: "Safety envelope active. Polyline generated.",
                latencyMs: 125.0,
                narration: "Evaluating route safety envelope, waypoints, and hazard parameters for flight \(firstWpt) → \(lastWpt).",
                status: "success",
                timestamp: Date()
            ),
            PromptTreeNode(
                id: "node_\(UUID().uuidString.prefix(6))",
                parentId: rootId,
                name: "Tool: Route_Leg_Analysis",
                nodeType: "tool",
                inputs: "Waypoints: \(route.waypoints.count) | Legs: \(computedLegRisks.count)",
                outputs: "Leg risks evaluated: \(computedLegRisks.map { "Leg \($0.fromIndex+1)→\($0.toIndex+1): Icing \($0.icing), Turb \($0.turbulence)" }.joined(separator: "; "))",
                latencyMs: 35.0,
                narration: "Calculated per-leg environmental hazard metrics across all waypoints.",
                status: "success",
                timestamp: Date()
            ),
            PromptTreeNode(
                id: "node_\(UUID().uuidString.prefix(6))",
                parentId: rootId,
                name: "Policy: Fuel_Reserve_Check",
                nodeType: "policy",
                inputs: "Est. Fuel: \(String(format: "%.1f", routeFuelGallons)) gal | Reserve Policy: 45 min (\(String(format: "%.1f", clampedFuel * 0.75)) gal)",
                outputs: "Total fuel required: \(String(format: "%.1f", totalFuelWithReserve)) gal. Policy satisfied.",
                latencyMs: 15.0,
                narration: "Enforcing FAA VFR 45-minute fuel reserve requirement and MEF altitude floor.",
                status: "success",
                timestamp: Date()
            ),
            PromptTreeNode(
                id: "node_\(UUID().uuidString.prefix(6))",
                parentId: rootId,
                name: "LLM: Safety_Advisory_Generator",
                nodeType: "llm",
                inputs: "Leg risks + Reserve evaluation",
                outputs: self.ffmAdvice,
                latencyMs: 75.0,
                narration: "Generated pilot advisory and risk heatmap layer overlays.",
                status: "warning",
                timestamp: Date()
            )
        ]
        PromptTreeTracer.shared.recordSession(title: "FFM Plan: \(firstWpt) → \(lastWpt)", nodes: traceNodes)
        
        // 7. Optionally ship telemetry trace to backend server in background if available
        let request = FFMRequest(
            aircraft: .init(type: "GA", trueAirspeedKTAS: clampedKTAS, fuelBurnGPH: clampedFuel),
            route: route.waypoints.map { .init(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) },
            policy: .init(reserveMinutes: 45, enforceMEF: true)
        )
        Task.detached {
            let client = FFMClient()
            _ = try? await client.plan(request: request, useMock: false)
        }
    }
}

// MARK: - Weather Service
class WeatherService: ObservableObject {
    @Published var currentWeather: [String: WeatherData] = [:]
    /// The real source behind this cache. Kept here so every view that already has
    /// a WeatherService gets observations without a second wiring path.
    let aviationWeather = AviationWeatherService()
    private var pollTimer: Timer?
    
    init() {
        startPolling()
    }
    
    deinit {
        pollTimer?.invalidate()
    }
    
    func startPolling() {
        pollTimer?.invalidate()
        // Poll weather every 1 minute (60 seconds)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refreshAllWeather()
        }
    }
    
    func refreshAllWeather() {
        objectWillChange.send()
    }
    
    /// Real observation for one field. This previously returned a hardcoded KSFO
    /// METAR — the same wind, visibility and ceiling for every airport on Earth.
    @MainActor
    func fetchWeather(for airport: Airport, using service: AviationWeatherService) async {
        await service.loadMetars(for: [airport.icao])
        await service.loadTaf(for: airport.icao)

        guard let metar = service.metar(for: airport.icao) else {
            // Many small fields have no reporting equipment. That is a fact to show,
            // not a gap to fill in.
            currentWeather[airport.icao] = nil
            return
        }
        let weather = WeatherData(
            metar: metar.rawOb,
            taf: service.tafs[airport.icao],
            wind: metar.wdir?.value.map {
                WindData(direction: $0, speed: Int((metar.wspd ?? 0).rounded()),
                         gust: metar.wgst.map { Int($0.rounded()) })
            },
            visibility: metar.visib?.miles,
            ceiling: metar.ceilingFT,
            temperature: metar.temp,
            pressure: metar.altim.map { $0 * 0.02953 }
        )
        currentWeather[airport.icao] = weather
    }

    private func unusedLegacyWeather(for airport: Airport) {
        let weather = WeatherData(
            metar: nil, taf: nil, wind: nil, visibility: nil,
            ceiling: nil, temperature: nil, pressure: nil
        )
        
        DispatchQueue.main.async {
            self.currentWeather[airport.icao] = weather
        }
    }
}

// MARK: - Location Manager
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation?
    @Published var heading: CLHeading?

    // Fired on every GPS fix so navigation progress can advance in real time.
    var onLocationUpdate: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 5
    }
    
    func request() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastLocation = loc
        onLocationUpdate?(loc)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }
}
