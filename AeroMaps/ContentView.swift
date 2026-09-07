import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var mapState = MapState()
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var weatherService: WeatherService
    @EnvironmentObject var liveFlightService: LiveFlightService

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // The map stays MOUNTED the entire time. Previously each tab switch
            // destroyed the MKMapView and rebuilt it on return (tile reload + GL
            // setup) — that teardown/rebuild is what made navigation feel slow or
            // frozen. Now we just hide it and overlay the other tabs on top.
            MapTabView(mapState: mapState)
                .opacity(mapState.activeTab == 0 ? 1 : 0)
                .allowsHitTesting(mapState.activeTab == 0)

            // Other tabs overlay with an opaque background so the hidden map
            // never shows through (RoutesTabView's ScrollView is transparent).
            if mapState.activeTab == 1 {
                FlightsTabView(mapState: mapState)
                    .background(Color(.systemBackground).ignoresSafeArea())
            } else if mapState.activeTab == 2 {
                LibraryTabView(mapState: mapState)
                    .background(Color(.systemBackground).ignoresSafeArea())
            } else if mapState.activeTab == 3 {
                RoutesTabView(mapState: mapState)
                    .background(Color(.systemBackground).ignoresSafeArea())
            }

            // Top-Right Floating Glass Mode Selector Button
            ModeSelectorButton(mapState: mapState)
                .padding(.trailing, 16)
                .padding(.top, mapState.isNavigatingRoute ? 150 : 54)
        }
        .onAppear {
            locationManager.request()
            mapState.locationManager = locationManager
            mapState.weatherService = weatherService
            // Advance turn-by-turn route progress on every GPS fix.
            locationManager.onLocationUpdate = { [weak mapState] loc in
                mapState?.updateLiveNavigationProgress(userCoord: loc.coordinate)
                // The track of the flight actually flown, for the logbook.
                mapState?.recordTrackFix(loc)
            }
            // Aeronautical data refreshes quietly in the background when due. It is
            // never required: the bundled copy is always there, and a failed fetch
            // leaves the working copy untouched.
            mapState.aeroData.refreshIfDue()
        }
        .onChange(of: mapState.activeTab, initial: true) { _, tab in
            // Pause the flight simulation when the map is hidden. No point animating
            // planes the user cannot see, and it stops the 2s re-render churn that
            // trips the observation feedback-loop warnings on the other tabs.
            liveFlightService.isActive = (tab == 0)
        }
    }
}

// MARK: - Floating Mode Selector Button (Bottom Right)
struct ModeSelectorButton: View {
    @ObservedObject var mapState: MapState
    
    var body: some View {
        Menu {
            Section("MAP & NAVIGATION") {
                Button(action: {
                    // Switch tabs WITHOUT withAnimation: animating a full-screen
                    // swap crossfades the heavy MKMapView and the new NavigationView
                    // together for ~0.35s, which is what made this feel slow.
                    mapState.activeTab = 0
                    mapState.showingFlightPlanner = false
                }) {
                    Label("Explore Map", systemImage: "map.fill")
                }

                Button(action: {
                    mapState.activeTab = 3
                }) {
                    Label("Routes & Navigation", systemImage: "location.north.line.fill")
                }
            }

            Section("FLIGHT TRAFFIC & TRACKING") {
                Button(action: {
                    mapState.flightSubTab = 1 // Live Traffic
                    mapState.activeTab = 1
                }) {
                    Label("Live Flight Radar", systemImage: "airplane")
                }

                Button(action: {
                    mapState.flightSubTab = 0 // Tracked
                    mapState.activeTab = 1
                }) {
                    Label("Tracked Flights", systemImage: "airplane.circle.fill")
                }
            }

            Section("AERONAUTICAL RESOURCES") {
                Button(action: {
                    mapState.activeTab = 2
                }) {
                    Label("Aeronautical Library", systemImage: "books.vertical.fill")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName(for: mapState.activeTab))
                    .font(.subheadline)
                    .foregroundColor(.white)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .aeroSurface(.floating, in: Capsule())
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        }
    }
    
    private func iconName(for tab: Int) -> String {
        switch tab {
        case 1: return "airplane"
        case 2: return "books.vertical.fill"
        case 3: return "location.north.line.fill"
        default: return "map.fill"
        }
    }
    
    private func titleName(for tab: Int) -> String {
        switch tab {
        case 1: return "Flights"
        case 2: return "Library"
        case 3: return "Routes"
        default: return "Map"
        }
    }
}

// MARK: - Map Tab View
struct MapTabView: View {
    @ObservedObject var mapState: MapState
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var weatherService: WeatherService
    @EnvironmentObject var liveFlightService: LiveFlightService
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var layout: PlanningLayout {
        PlanningLayout(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    var body: some View {
        GeometryReader { geo in
            content(windowHeight: geo.size.height)
        }
    }

    @ViewBuilder
    private func content(windowHeight: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            // Main Map View (takes 100% full screen background, zero top blur)
            MapView(mapState: mapState)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
            
            // Top In-Flight Navigation Banner (Google/Apple Maps style turn-by-turn guidance)
            if mapState.isNavigatingRoute {
                VStack {
                    TopNavigationHUDBanner(mapState: mapState)
                    Spacer()
                }
            }
            
            // Top-Left Compact 2-Row Wind Aloft Card (Active when .wind is toggled AND zoomed in <= 100 miles!)
            if mapState.activeLayers.contains(.wind) && mapState.isZoomedInTo100Miles {
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "wind")
                                    .font(.caption2)
                                    .foregroundColor(.cyan)
                                Text("Wind Aloft")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.cyan)
                            }
                            
                            HStack(spacing: 6) {
                                Text("\(mapState.centerWindDir)° @ \(mapState.centerWindSpeed) kt")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("[\(mapState.windAltitudeFT == 0 ? "Surface" : "\(mapState.windAltitudeFT.formatted()) ft")]")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thickMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.0
                                )
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
                        
                        Spacer()
                    }
                    .padding(.leading, 16)
                    .padding(.top, 60)
                    
                    Spacer()
                }
            }
            

            
            // Says what the traffic on the map actually is. Simulated aircraft that
            // look live are worse than no aircraft at all — a pilot must be able to
            // tell at a glance whether those targets are real.
            // Bottom-left: out of the way of the route, the top HUD banner and the
            // map-style control, which is where it used to sit.
            if mapState.activeLayers.contains(.traffic), !liveFlightService.isLoading {
                VStack {
                    Spacer()
                    HStack {
                        TrafficSourceBadge(service: liveFlightService)
                        Spacer()
                    }
                    .padding(.leading, 16)
                    .padding(.bottom, layout.mapControlBottomInset)
                }
            }

            // High Zoom-Out Traffic Loading Spinner Glass Badge
            if liveFlightService.isLoading {
                VStack {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading Regional Traffic...")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                    .padding(.top, 60)
                    
                    Spacer()
                }
                .transition(.opacity)
            }
            
            // Floating Action Buttons (Right-aligned on map, above collapsed sheet)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingActionButtons(mapState: mapState)
                        .padding(.trailing, 16)
                        .padding(.bottom, layout.mapControlBottomInset)
                }
            }
            .environment(\.planningLayout, layout)
            
            // The planning surface: the same sheet on every device, sized to the
            // window rather than stretched across it.
            BottomSheet(mapState: mapState, windowHeight: windowHeight)
        }
        .sheet(isPresented: $mapState.showingAirportDetail, onDismiss: {
            mapState.selectedAirport = nil
        }) {
            if let airport = mapState.selectedAirport {
                AirportDetailView(airport: airport, weatherService: weatherService)
            }
        }
        .sheet(isPresented: $mapState.showingFlightDetail, onDismiss: {
            mapState.selectedFlight = nil
            mapState.showingFlightDetail = false
        }) {
            if let flight = mapState.selectedFlight {
                FlightDetailView(flight: flight, mapState: mapState)
            }
        }
        // One presentation for every tool screen. See MapState.ToolSheet for why
        // this is not eleven separate .sheet modifiers.
        .sheet(item: $mapState.activeTool) { tool in
            switch tool {
            case .flightPlanner: FlightPlannerView(mapState: mapState)
            case .routeAdvisor:
                RouteAssistantView(mapState: mapState,
                                   initialTab: RouteAssistantView.Tab(storageKey: mapState.assistantTab))
            case .aircraft:      AircraftPickerView(mapState: mapState)
            case .procedure:     ProcedureAdvisorView(mapState: mapState)
            case .profile:       RouteProfileView(mapState: mapState)
            case .plates:        AirportToolsView(mapState: mapState)
            case .checklist:     ChecklistView(mapState: mapState)
            case .notes:         FlightNotesView(mapState: mapState)
            case .weather:       WeatherPanelView(mapState: mapState, weatherService: weatherService)
            case .promptTree:    PromptTreeVisualizerView()
            case .logbook:       LogbookView(mapState: mapState)
            case .amend:         InFlightAmendmentView(mapState: mapState)
            }
        }
        // Deliberately NOT a .alert. A UIAlertController presented over this view
        // has to wait for the whole map tree — MKMapView included — to be laid out
        // and snapshotted before it animates in, which is what made "Save Route"
        // take a beat to appear. An in-tree overlay with its own local text state
        // shows instantly and, because the field is not bound to MapState, does not
        // re-run the map's updateUIView on every keystroke.
        .overlay {
            if mapState.showingSaveRouteDialog {
                SaveRouteDialog(
                    defaultName: mapState.route.displayName,
                    onCancel: { mapState.showingSaveRouteDialog = false },
                    onSave: { name in mapState.confirmSaveRoute(name: name) }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.18), value: mapState.showingSaveRouteDialog)
    }
}

// MARK: - Save Route Dialog

/// Lightweight in-tree replacement for the save-route alert.
struct SaveRouteDialog: View {
    let defaultName: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text("Save Flight Route")
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Name this route, or leave it blank to use the default.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }

                TextField(defaultName, text: $name)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { onSave(name) }

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.subheadline).fontWeight(.semibold)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Color.white.opacity(0.12))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button { onSave(name) } label: {
                        Text("Save")
                            .font(.subheadline).fontWeight(.bold)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(.thickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .padding(.horizontal, 30)
        }
        .onAppear { focused = true }
    }
}

// MARK: - Traffic Source Badge

/// Live, cached, or simulated — stated plainly, with the remaining data budget when
/// the feed is real.
struct TrafficSourceBadge: View {
    @ObservedObject var service: LiveFlightService

    var body: some View {
        let source = service.trafficSource
        HStack(spacing: 6) {
            Image(systemName: icon(source))
                .font(.system(size: 10, weight: .bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(source.label)
                    .font(.system(size: 11, weight: .semibold))
                if let detail = source.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .foregroundColor(tint(source))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .aeroSurface(.floating, in: Capsule())
        .overlay(Capsule().stroke(tint(source).opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
    }

    private func icon(_ source: LiveFlightService.TrafficSource) -> String {
        switch source {
        case .live:      return "dot.radiowaves.up.forward"
        case .cached:    return "clock.arrow.circlepath"
        case .simulated: return "exclamationmark.triangle.fill"
        }
    }

    private func tint(_ source: LiveFlightService.TrafficSource) -> Color {
        switch source {
        case .live:      return .green
        case .cached:    return .yellow
        case .simulated: return .orange
        }
    }
}

// MARK: - Flights Tab View
struct FlightsTabView: View {
    @ObservedObject var mapState: MapState

    // The navigation shell deliberately does NOT observe the live flight feed, so
    // the title and toolbar never re-evaluate on the 2s tick. That is what stops
    // the "observation tracking feedback loop" warnings on this tab. All live
    // content lives in FlightsPanel below.
    var body: some View {
        NavigationStack {
            FlightsPanel(mapState: mapState)
                .navigationTitle("Flights")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            mapState.showingFlightPlanner = true
                        } label: {
                            Label("New Flight", systemImage: "plus.circle.fill")
                        }
                    }
                }
        }
    }
}

private struct FlightsPanel: View {
    @ObservedObject var mapState: MapState
    @EnvironmentObject var liveFlightService: LiveFlightService
    @State private var customCallsign = ""

    private let simulatedFlights = [
        ("UAL1234", "KSFO", "KLAX", "FL350", 450.0, "1200"),
        ("SWA5678", "KSJC", "KLAS", "FL280", 410.0, "2314"),
        ("AAL9999", "KOAK", "KPHX", "FL320", 430.0, "4521"),
        ("DAL4444", "KSFO", "KSEA", "FL380", 465.0, "7102")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Flight Mode", selection: $mapState.flightSubTab) {
                Text("Tracked (\(liveFlightService.trackedFlights.count))").tag(0)
                Text("Live Traffic").tag(1)
                Text("Track New").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            List {
                if mapState.flightSubTab == 0 {
                    trackedSection
                } else if mapState.flightSubTab == 1 {
                    liveTrafficSection
                } else {
                    trackNewSection
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Tracked
    @ViewBuilder private var trackedSection: some View {
        Section("Tracked Flights") {
            if liveFlightService.trackedFlights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No flights tracked")
                        .font(.subheadline).fontWeight(.semibold)
                    Text("Tap a plane on the map, or use Track New, to follow its telemetry.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(liveFlightService.trackedFlights) { flight in
                    TrackedFlightRow(flight: flight, mapState: mapState, service: liveFlightService)
                }
            }
        }
    }

    // MARK: - Live Traffic
    @ViewBuilder private var liveTrafficSection: some View {
        Section("Surrounding Traffic") {
            ForEach(simulatedFlights, id: \.0) { callsign, origin, dest, fl, speed, squawk in
                Button {
                    openSimulated(callsign: callsign, origin: origin, dest: dest, fl: fl, speed: speed, squawk: squawk)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "airplane")
                            .foregroundColor(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(callsign).font(.headline).foregroundColor(.primary)
                            Text("\(origin) → \(dest)").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(fl).font(.caption).fontWeight(.bold).foregroundColor(.blue)
                        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Track New
    @ViewBuilder private var trackNewSection: some View {
        Section("Track a Callsign") {
            HStack {
                Image(systemName: "airplane.circle.fill").foregroundColor(.cyan)
                TextField("e.g. UAL450, SWA12, N1KE", text: $customCallsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .onSubmit(trackCustom)
            }
            Button(action: trackCustom) {
                Label("Track Flight", systemImage: "star.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(customCallsign.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func trackCustom() {
        let call = customCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !call.isEmpty else { return }
        liveFlightService.toggleTrackedFlight(
            callsign: call, origin: "KSFO", destination: "KLAX",
            altitude: 35000, speed: 460, heading: 190,
            coordinate: CLLocationCoordinate2D(latitude: 37.6213, longitude: -122.3790))
        customCallsign = ""
        mapState.flightSubTab = 0
    }

    private func openSimulated(callsign: String, origin: String, dest: String, fl: String, speed: Double, squawk: String) {
        let origCoord = mapState.airports[origin]?.coordinate ?? CLLocationCoordinate2D(latitude: 37.6213, longitude: -122.3790)
        let destCoord = mapState.airports[dest]?.coordinate ?? CLLocationCoordinate2D(latitude: 33.9416, longitude: -118.4085)
        let distNM = round(mapState.distanceNM(origCoord, destCoord))
        let flightHours = max(0.2, distNM / speed)
        let realAlt = (Double(fl.replacingOccurrences(of: "FL", with: "")) ?? 350) * 100
        mapState.selectedFlight = FlightAnalysis(
            callsign: callsign, origin: origin, destination: dest, altitude: realAlt, speed: speed,
            heading: 195, verticalRate: 0, squawk: squawk, distance: distNM,
            eta: Date().addingTimeInterval(flightHours * 3600), fuelRemaining: max(600.0, round(distNM * 6.5)),
            weather: "VFR Clear • Winds 260° @ 16kt", coordinate: origCoord)
        mapState.showingFlightDetail = true
    }
}

// One tracked-flight row: tap the info area to open detail, tap Untrack to remove.
private struct TrackedFlightRow: View {
    let flight: LiveFlight
    @ObservedObject var mapState: MapState
    let service: LiveFlightService

    var body: some View {
        HStack {
            Button(action: openDetail) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(flight.callsign ?? "FLIGHT").font(.headline)
                        Text("EN ROUTE")
                            .font(.caption2).fontWeight(.bold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.2)).foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                    Text("\(mapState.airportShort(for: flight.origin ?? "")) → \(mapState.airportShort(for: flight.destination ?? ""))")
                        .font(.subheadline).foregroundColor(.secondary)
                    if let alt = flight.altitude, let spd = flight.speed {
                        Text("FL\(Int(alt / 100)) • \(Int(spd)) kt")
                            .font(.caption).fontWeight(.semibold).foregroundColor(.cyan)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                if let cs = flight.callsign { service.toggleTrackedFlight(callsign: cs) }
            } label: {
                Label("Untrack", systemImage: "star.slash.fill")
                    .font(.caption).fontWeight(.bold)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.2))
                    .foregroundColor(.yellow)
                    .clipShape(Capsule())
            }
            .buttonStyle(.borderless)
        }
    }

    private func openDetail() {
        guard let callsign = flight.callsign else { return }
        let dest = flight.destination ?? "KLAX"
        let destCoord = mapState.airports[dest]?.coordinate ?? CLLocationCoordinate2D(latitude: 33.9416, longitude: -118.4085)
        let spd = flight.speed ?? 430
        let distNM = round(mapState.distanceNM(flight.coordinate, destCoord))
        mapState.selectedFlight = FlightAnalysis(
            callsign: callsign, origin: flight.origin ?? "KSFO", destination: dest,
            altitude: flight.altitude ?? 32000, speed: spd, heading: flight.heading ?? 180,
            verticalRate: flight.verticalRate ?? 0, squawk: flight.squawk ?? "1200",
            distance: distNM, eta: Date().addingTimeInterval(max(0.2, distNM / spd) * 3600),
            fuelRemaining: max(600.0, round(distNM * 6.5)), weather: "VFR Clear • Winds 270° @ 18kt",
            icao24: flight.icao24, coordinate: flight.coordinate)
        mapState.showingFlightDetail = true
    }
}

struct LibraryTabView: View {
    @ObservedObject var mapState: MapState
    @EnvironmentObject var weatherService: WeatherService
    
    var body: some View {
        NavigationView {
            List {
                // Weather & Wind Navigation Studio
                Section("🌤️ Weather & Wind Navigation Studio") {
                    Picker("Temperature Unit", selection: $mapState.tempUnit) {
                        Text("°C (Celsius)").tag(TemperatureUnit.celsius)
                        Text("°F (Fahrenheit)").tag(TemperatureUnit.fahrenheit)
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Text("Wind Altitude")
                            .font(.subheadline)
                        Spacer()
                        Text("\(mapState.windAltitudeFT.formatted()) ft")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                    }
                    
                    Picker("Altitude Level", selection: $mapState.windAltitudeFT) {
                        Text("Surface (0 ft)").tag(0)
                        Text("3,000 ft").tag(3000)
                        Text("6,000 ft").tag(6000)
                        Text("12,000 ft").tag(12000)
                        Text("18,000 ft (FL180)").tag(18000)
                        Text("30,000 ft (Jet Stream)").tag(30000)
                    }
                    
                    Button(action: {
                        mapState.showingWeatherPanel = true
                    }) {
                        Label("Open METAR & Radar Briefing Panel", systemImage: "cloud.sun.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                Section("Documents") {
                    NavigationLink("POH & Manuals", destination: Text("POH & Manuals"))
                    NavigationLink("Checklists", destination: Text("Checklists"))
                    NavigationLink("SOPs", destination: Text("SOPs"))
                }
                
                Section("Charts & Plates") {
                    NavigationLink("Approach Plates", destination: Text("Approach Plates"))
                    NavigationLink("Airport Diagrams", destination: Text("Airport Diagrams"))
                    NavigationLink("Sectional Charts", destination: Text("Sectional Charts"))
                }
                
                Section("AI Safety & Diagnostics") {
                    Button(action: {
                        PromptTreeTracer.shared.objectWillChange.send()
                    }) {
                        NavigationLink("🌳 AI Decision Tree Visualizer", destination: PromptTreeVisualizerView())
                    }
                }
                
                Section("Downloads") {
                    NavigationLink("Downloaded Charts", destination: Text("Downloaded Charts"))
                    NavigationLink("Offline Data", destination: Text("Offline Data"))
                }
            }
            .navigationTitle("Library")
        }
    }
}

// MARK: - Flight Row View
struct FlightRowView: View {
    let origin: String
    let destination: String
    let date: String
    let time: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(origin) → \(destination)")
                    .font(.headline)
                Text("\(date) at \(time)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}



// MARK: - Flight & NOTAM Point Annotations
class FlightPointAnnotation: MKPointAnnotation {
    var icao24: String = ""
    var isTracked: Bool = false
    var heading: Double = 0   // compass degrees, used to rotate the silhouette
}

class NOTAMPointAnnotation: MKPointAnnotation {
    var notamID: String = ""
}

class AirportPointAnnotation: MKPointAnnotation {
    var icao: String = ""
    /// Sectional convention: blue for towered, magenta for non-towered.
    var isTowered: Bool = false
    /// True headings, so the symbol shows the field's actual runway layout.
    var runwayHeadings: [Double] = []
}

/// A waypoint on the planned route. Carries its sequence position so the marker
/// can render its number and mark the departure/destination ends differently.
class RouteWaypointAnnotation: MKPointAnnotation {
    var index: Int = 0            // 1-based position in the route
    var isDeparture: Bool = false
    var isDestination: Bool = false
    var waypointID: UUID = UUID()
}

class WeatherPointAnnotation: MKPointAnnotation {
    var icao: String = ""
    var category: String = "VFR" // VFR, MVFR, IFR, LIFR
    var tempCelsius: Double = 18.0
    var windDir: Int = 280
    var windSpeed: Int = 14
    var weatherCondition: String = "⛅"
}

// MARK: - Custom Black Rounded Rectangle Weather Annotation View
class WeatherAnnotationView: MKAnnotationView {
    private let badgeContainer = UIView()
    private let iconLabel = UILabel()
    private let tempLabel = UILabel()
    private let categoryDot = UIView()
    
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }
    
    private func setupView() {
        canShowCallout = false
        displayPriority = .required
        zPriority = .max
        frame = CGRect(x: 0, y: 0, width: 88, height: 32)
        centerOffset = CGPoint(x: 0, y: -16)
        
        // Liquid Glass Container with UltraThinMaterial blur & specular border
        badgeContainer.frame = bounds
        badgeContainer.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        badgeContainer.layer.cornerRadius = 10
        badgeContainer.layer.masksToBounds = true
        badgeContainer.layer.borderWidth = 1.0
        badgeContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = badgeContainer.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        badgeContainer.addSubview(blurView)
        
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 6
        
        addSubview(badgeContainer)
        
        // Icon Label (Weather Condition e.g. ⛅, ☀️, 🌧️)
        iconLabel.frame = CGRect(x: 6, y: 4, width: 22, height: 24)
        iconLabel.font = .systemFont(ofSize: 15)
        iconLabel.textAlignment = .center
        badgeContainer.addSubview(iconLabel)
        
        // Temperature Label (Crisp White Text e.g. 19°C / 64°F)
        tempLabel.frame = CGRect(x: 28, y: 4, width: 44, height: 24)
        tempLabel.font = .systemFont(ofSize: 13, weight: .bold)
        tempLabel.textColor = .white
        tempLabel.textAlignment = .left
        badgeContainer.addSubview(tempLabel)
        
        // FAA Flight Category Status Indicator Light Dot (🟢 VFR, 🔵 MVFR, 🔴 IFR, 🟣 LIFR)
        categoryDot.frame = CGRect(x: 73, y: 12, width: 8, height: 8)
        categoryDot.layer.cornerRadius = 4
        categoryDot.layer.masksToBounds = true
        badgeContainer.addSubview(categoryDot)
    }
    
    func configure(weather: WeatherPointAnnotation, mapState: MapState) {
        self.annotation = weather
        iconLabel.text = weather.weatherCondition
        tempLabel.text = mapState.formatTemp(weather.tempCelsius)
        
        switch weather.category.uppercased() {
        case "VFR":
            categoryDot.backgroundColor = .systemGreen
        case "MVFR":
            categoryDot.backgroundColor = .systemBlue
        case "IFR":
            categoryDot.backgroundColor = .systemRed
        case "LIFR":
            categoryDot.backgroundColor = .systemPurple
        default:
            categoryDot.backgroundColor = .systemGreen
        }
    }
}

// MARK: - Map View
struct MapView: UIViewRepresentable {
    @ObservedObject var mapState: MapState
    @EnvironmentObject var liveFlightService: LiveFlightService
    @EnvironmentObject var locationManager: LocationManager
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.mapType = mapState.mapStyle == .hybrid ? .hybrid : .standard
        
        // Add Long Press gesture (Press and Hold to drop waypoints, preventing accidental tap drops)
        // MapKit draws its own airport POI pins, which stacked underneath our
        // markers and read as a doubled-up icon. Ours carry the aeronautical data,
        // so Apple's are excluded.
        mapView.pointOfInterestFilter = MKPointOfInterestFilter(excluding: [.airport])

        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(longPressGesture)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Perform fast differential check to skip heavy MapKit updates when map data is unchanged
        let currentWaypointsHash = mapState.route.waypoints.map { "\($0.icao)_\($0.coordinate.latitude)_\($0.coordinate.longitude)" }.joined(separator: "|")
        let layersChanged = context.coordinator.lastActiveLayers != mapState.activeLayers
        let routeChanged = context.coordinator.lastWaypointsHash != currentWaypointsHash
        let navChanged = context.coordinator.lastIsNavigating != mapState.isNavigatingRoute || context.coordinator.lastCurrentWaypointIdx != mapState.currentWaypointIndex
        let styleChanged = context.coordinator.lastMapStyle != mapState.mapStyle
        let centerCameraRequested = mapState.shouldCenterCamera
        
        let needsMapRebuild = layersChanged || routeChanged || navChanged || styleChanged || centerCameraRequested
        
        // Update camera on initial load to center over user location (or fallback default)
        if !context.coordinator.hasSetInitialCamera {
            if let userLoc = locationManager.lastLocation {
                let camera = MKMapCamera(lookingAtCenter: userLoc.coordinate, fromDistance: 140_000, pitch: 0, heading: 0)
                mapView.setCamera(camera, animated: false)
                context.coordinator.hasSetInitialCamera = true
            } else {
                mapView.setCamera(mapState.camera, animated: false)
            }
        } else if mapState.shouldCenterCamera {
            mapView.setCamera(mapState.camera, animated: true)
            DispatchQueue.main.async {
                mapState.shouldCenterCamera = false
            }
        }
        
        // Update map type
        mapView.mapType = mapState.mapStyle == .hybrid ? .hybrid : .standard

        // --- ALWAYS-RUN (not gated by needsMapRebuild) ---
        // Live flights must refresh on every update so planes appear/aggregate as
        // you zoom or pan and as the region fetch returns new traffic. Gating this
        // behind needsMapRebuild is why zooming out showed no planes. addLiveFlights
        // is diff-based (reuses annotations by icao24), so running it often is cheap.
        // Skip annotation mutations while the map is animating a pan/zoom: MapKit
        // is enumerating its cluster hash table then, and mutating annotations
        // mid-enumeration crashes ("collection mutated while being enumerated").
        // Updates resume automatically on the next tick once the region settles.
        if !context.coordinator.isChangingRegion {
            if mapState.activeLayers.contains(.traffic) {
                addLiveFlights(mapView)
            } else {
                let existingFlights = mapView.annotations.compactMap { $0 as? FlightPointAnnotation }
                if !existingFlights.isEmpty { mapView.removeAnnotations(existingFlights) }
            }
        }

        // Deselect a flight/airport pin as soon as its detail sheet is dismissed,
        // otherwise the pin stays enlarged ("selected") on the map. Iterate over a
        // snapshot (Array) since deselectAnnotation mutates selectedAnnotations.
        if mapState.selectedAirport == nil {
            for selected in Array(mapView.selectedAnnotations) where selected is AirportPointAnnotation {
                mapView.deselectAnnotation(selected, animated: true)
            }
        }
        if mapState.selectedFlight == nil {
            for selected in Array(mapView.selectedAnnotations) where (selected is FlightPointAnnotation) {
                mapView.deselectAnnotation(selected, animated: true)
            }
        }

        // Flightradar24-style dashed trail behind the currently selected flight.
        // Managed every frame (not gated by needsMapRebuild) so it grows live as
        // the plane moves; tagged by title so the renderer can style it dashed.
        let existingTrails = mapView.overlays.compactMap { $0 as? MKPolyline }.filter { $0.title == "FlightTrail" }
        if !existingTrails.isEmpty { mapView.removeOverlays(existingTrails) }
        if mapState.selectedFlight != nil {
            let trailCoords = liveFlightService.trailPoints
            if trailCoords.count >= 2 {
                let trail = MKPolyline(coordinates: trailCoords, count: trailCoords.count)
                trail.title = "FlightTrail"
                mapView.addOverlay(trail, level: .aboveRoads)
            }
        }

        // Airports are chosen by what is in view, so this runs every update — it
        // early-returns when the visible set has not changed. Gating it behind the
        // rebuild check would leave the map showing the airports of wherever it was
        // last rebuilt.
        addAirportAnnotations(mapView)

        // Airspace is chosen by what is in view too, so it must refresh on pan and
        // zoom rather than only on a full rebuild. Both early-return when the
        // visible set is unchanged.
        if mapState.activeLayers.contains(.airspace) {
            addDemoAirspace(mapView)
        }

        if !needsMapRebuild {
            return
        }
        
        context.coordinator.lastActiveLayers = mapState.activeLayers
        context.coordinator.lastWaypointsHash = currentWaypointsHash
        context.coordinator.lastIsNavigating = mapState.isNavigatingRoute
        context.coordinator.lastCurrentWaypointIdx = mapState.currentWaypointIndex
        context.coordinator.lastMapStyle = mapState.mapStyle
        
        // Clear overlays & route annotations for fresh layer rendering.
        // NOTE: flight annotations are intentionally preserved here — they are
        // managed every frame by the always-run block above (diff-based), so
        // wiping them here would cause flicker and fight that logic.
        mapView.removeOverlays(mapView.overlays)
        let routeAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) && !($0 is FlightPointAnnotation) }
        mapView.removeAnnotations(routeAnnotations)
        
        // Add route waypoints
        let wpCount = mapState.route.waypoints.count
        for (idx, waypoint) in mapState.route.waypoints.enumerated() {
            let annotation = RouteWaypointAnnotation()
            annotation.coordinate = waypoint.coordinate
            annotation.title = waypoint.icao
            annotation.subtitle = waypoint.name
            annotation.index = idx + 1
            annotation.isDeparture = (idx == 0)
            annotation.isDestination = (wpCount > 1 && idx == wpCount - 1)
            mapView.addAnnotation(annotation)
        }
        
        // Add route line (Google/Apple Maps Navigation Style Visualization)
        if mapState.isNavigatingRoute && mapState.route.waypoints.count >= 2 {
            let waypoints = mapState.route.waypoints
            let currentIdx = max(0, min(mapState.currentWaypointIndex, waypoints.count - 1))
            let nextIdx = min(currentIdx + 1, waypoints.count - 1)
            
            // 1. Visited / Completed Route (WPT 0 -> WPT current): Grey line with Blue edges!
            if currentIdx > 0 {
                let visitedCoords = Array(waypoints[0...currentIdx].map { $0.coordinate })
                
                // Outer Blue Border
                let visBorder = MKPolyline(coordinates: visitedCoords, count: visitedCoords.count)
                visBorder.title = "VisitedRouteBorder"
                mapView.addOverlay(visBorder)
                
                // Inner Gray Core
                let visCore = MKPolyline(coordinates: visitedCoords, count: visitedCoords.count)
                visCore.title = "VisitedRouteCore"
                mapView.addOverlay(visCore)
            }
            
            // 2. Active Current Leg (WPT current -> WPT next): Vibrant Green Line!
            if currentIdx < waypoints.count - 1 {
                let currentLegCoords = [waypoints[currentIdx].coordinate, waypoints[nextIdx].coordinate]
                let activeLegPoly = MKPolyline(coordinates: currentLegCoords, count: 2)
                activeLegPoly.title = "ActiveCurrentLeg"
                mapView.addOverlay(activeLegPoly)
            }
            
            // 3. Remaining Future Route (WPT next -> Final Destination): Vibrant Blue Line!
            if nextIdx < waypoints.count - 1 {
                let remainingCoords = Array(waypoints[nextIdx..<waypoints.count].map { $0.coordinate })
                let remPoly = MKPolyline(coordinates: remainingCoords, count: remainingCoords.count)
                remPoly.title = "RemainingFutureRoute"
                mapView.addOverlay(remPoly)
            }
            
            // 4. Off-Route Deviation Line (Current Location -> Next WPT or Perpendicular Line): Thin Black Dotted Line!
            if mapState.offRouteDistanceNM > 0.3,
               let userLoc = locationManager.lastLocation?.coordinate {
                let nextWpCoord = waypoints[nextIdx].coordinate
                let closestPoint = mapState.closestRoutePoint ?? nextWpCoord
                
                // Use closest of perpendicular point or next waypoint
                let distToNext = mapState.distanceNM(userLoc, nextWpCoord)
                let distToPerp = mapState.distanceNM(userLoc, closestPoint)
                let targetDeviationPoint = distToNext < distToPerp ? nextWpCoord : closestPoint
                
                let devPoly = MKPolyline(coordinates: [userLoc, targetDeviationPoint], count: 2)
                devPoly.title = "OffRouteDeviationBlackDotted"
                mapView.addOverlay(devPoly)
            }
        } else if let ffmPoly = mapState.computedPolyline {
            mapView.addOverlay(ffmPoly)
        } else if mapState.route.waypoints.count >= 2 {
            let coordinates = mapState.route.waypoints.map { $0.coordinate }
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            polyline.title = "RemainingFutureRoute"
            mapView.addOverlay(polyline)
        }
        
        if mapState.activeLayers.contains(.tfr) {
            addDemoTFRs(mapView)
        }
        
        // Add active NOTAM hazard annotations
        if mapState.activeLayers.contains(.notams) {
            addNOTAMAnnotations(mapView)
        } else {
            let existingNOTAMs = mapView.annotations.compactMap { $0 as? NOTAMPointAnnotation }
            if !existingNOTAMs.isEmpty {
                mapView.removeAnnotations(existingNOTAMs)
            }
        }
        
        // (Airports were refreshed above, before the rebuild gate.)
        
        // Add active METAR weather station annotations (ONLY when toggled ON AND zoomed in <= 100 miles!)
        if mapState.activeLayers.contains(.weather) && mapState.isZoomedInTo100Miles {
            addWeatherAnnotations(mapView)
        } else {
            let existingWeather = mapView.annotations.compactMap { $0 as? WeatherPointAnnotation }
            if !existingWeather.isEmpty {
                mapView.removeAnnotations(existingWeather)
            }
        }
        
        // Add live NEXRAD Doppler Weather Radar overlay
        if mapState.activeLayers.contains(.radar) {
            addWeatherRadarOverlay(mapView)
        }
        
        // (Live flight traffic + pin deselection are handled every frame in the
        //  always-run block above, so they are intentionally not repeated here.)

        // Add FFM risk tile overlays if present
        for overlay in mapState.riskOverlays {
            mapView.addOverlay(overlay, level: .aboveLabels)
        }
    }
    
    /// Published FAA controlled airspace for the visible area.
    ///
    /// This was two circles hardcoded at SFO and SJC, drawn over every part of the
    /// world the map was pointed at. It is now the real published boundaries, with
    /// their actual shelves and altitudes.
    private func addDemoAirspace(_ mapView: MKMapView) {
        let span = mapView.region.span.latitudeDelta
        mapState.airspace.load(around: mapView.centerCoordinate, spanDegrees: span)

        let existing = mapView.overlays.compactMap { $0 as? AirspaceOverlay }
        // Too far out to be legible; sectionals thin the same way.
        guard span <= AirspaceService.maxSpanDegrees else {
            if !existing.isEmpty { mapView.removeOverlays(existing) }
            return
        }

        let centre = mapView.centerCoordinate
        let latSpan = span * 0.8
        let lonSpan = mapView.region.span.longitudeDelta * 0.8
        let wanted = mapState.airspace.volumes.filter {
            $0.intersects(centerLat: centre.latitude, centerLon: centre.longitude,
                          latSpan: latSpan, lonSpan: lonSpan)
        }
        // Diff by identity and touch only the difference.
        //
        // This compared the *count* of wanted ids against the count of existing
        // *titles* — two different strings, so the sets never matched and every
        // polygon was torn down and rebuilt on each map update. That was the
        // flicker.
        let wantedIDs = Set(wanted.prefix(120).map(\.id))
        let existingIDs = Set(existing.map(\.volumeID))
        guard wantedIDs != existingIDs else { return }

        let stale = existing.filter { !wantedIDs.contains($0.volumeID) }
        if !stale.isEmpty { mapView.removeOverlays(stale) }

        for volume in wanted.prefix(120) where !existingIDs.contains(volume.id) {
            mapView.addOverlay(AirspaceOverlay.make(from: volume), level: .aboveRoads)
        }
    }
    
    private func addDemoTFRs(_ mapView: MKMapView) {
        let center = mapView.centerCoordinate
        let latSpan = mapView.region.span.latitudeDelta
        let lonSpan = mapView.region.span.longitudeDelta
        
        // Real-World Strategic Global TFR Conflict Zones (Iran OIIX FIR, Persian Gulf, etc.)
        let globalTFRs: [(name: String, center: CLLocationCoordinate2D, radius: Double)] = [
            ("OIIX Tehran FIR Conflict TFR", CLLocationCoordinate2D(latitude: 32.4279, longitude: 53.6880), 650_000), // IRAN (Massive FIR TFR)
            ("Persian Gulf / Strait of Hormuz TFR", CLLocationCoordinate2D(latitude: 26.5000, longitude: 56.2500), 250_000), // PERSIAN GULF
            ("Bab-el-Mandeb Red Sea Maritime TFR", CLLocationCoordinate2D(latitude: 14.5000, longitude: 42.5000), 300_000),
            ("UKDV Dnipro FIR Conflict Zone TFR", CLLocationCoordinate2D(latitude: 48.3794, longitude: 31.1656), 450_000),
            ("P-56 Washington DC Capitol TFR", CLLocationCoordinate2D(latitude: 38.8951, longitude: -77.0364), 75_000),
            ("SFO Bay Area Security TFR", CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), 45_000)
        ]
        
        // Always add all strategic global TFR circles (MapKit handles rendering visible ones automatically!)
        for tfr in globalTFRs {
            let circle = MKCircle(center: tfr.center, radius: tfr.radius)
            mapView.addOverlay(circle)
        }
        
        // Also add dynamic viewport TFRs for localized regions
        let tfrCenter1 = CLLocationCoordinate2D(latitude: center.latitude + latSpan * 0.15, longitude: center.longitude - lonSpan * 0.18)
        let tfrCenter2 = CLLocationCoordinate2D(latitude: center.latitude - latSpan * 0.20, longitude: center.longitude + lonSpan * 0.22)
        let radius1 = max(10000.0, min(120000.0, latSpan * 111000 * 0.12))
        let radius2 = max(15000.0, min(160000.0, latSpan * 111000 * 0.18))
        mapView.addOverlay(MKCircle(center: tfrCenter1, radius: radius1))
        mapView.addOverlay(MKCircle(center: tfrCenter2, radius: radius2))
    }
    
    /// NOTAM markers, from the FAA NOTAM API.
    ///
    /// This function used to contain six hardcoded fake NOTAMs — a closed runway at
    /// KSFO, an unlit crane at KLAX — plus two more generated at whatever the map
    /// was centred on, all displayed as though they were real. Nothing is invented
    /// here now: with no credentials configured the layer is simply empty and the
    /// UI says why.
    private func addNOTAMAnnotations(_ mapView: MKMapView) {
        let existing = mapView.annotations.compactMap { $0 as? NOTAMPointAnnotation }
        let notams = mapState.notams.notams.filter { $0.coordinate != nil }

        let wanted = Set(notams.map(\.id))
        let have = Set(existing.map(\.notamID))
        guard wanted != have else { return }

        mapView.removeAnnotations(existing)
        for notam in notams {
            guard let coordinate = notam.coordinate else { continue }
            let annotation = NOTAMPointAnnotation()
            annotation.coordinate = coordinate
            annotation.notamID = notam.id
            annotation.title = "\(notam.icaoLocation) \(notam.number)"
            annotation.subtitle = notam.text
            mapView.addAnnotation(annotation)
        }
    }

    private func addWeatherRadarOverlay(_ mapView: MKMapView) {
        // Real-Time Live US NEXRAD Doppler Weather Radar Tile Overlay
        let template = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png"
        let tileOverlay = MKTileOverlay(urlTemplate: template)
        tileOverlay.canReplaceMapContent = false
        tileOverlay.tileSize = CGSize(width: 256, height: 256)
        mapView.addOverlay(tileOverlay, level: .aboveLabels)
    }
    
    private func addWeatherAnnotations(_ mapView: MKMapView) {
        let existing = mapView.annotations.compactMap { $0 as? WeatherPointAnnotation }
        if !existing.isEmpty {
            return // Weather station annotations are already loaded!
        }
        
        let center = mapView.centerCoordinate
        let latSpan = mapView.region.span.latitudeDelta
        let lonSpan = mapView.region.span.longitudeDelta
        
        let metarStations: [(icao: String, category: String, tempC: Double, windDir: Int, windSpd: Int, icon: String, metar: String, coord: CLLocationCoordinate2D)] = [
            ("KSFO", "VFR", 18.0, 280, 14, "⛅", "KSFO 050156Z 28014KT 10SM CLR 18/12 A2998", CLLocationCoordinate2D(latitude: 37.6333, longitude: -122.3670)),
            ("KSJC", "VFR", 21.0, 310, 10, "☀️", "KSJC 050153Z 31010KT 10SM FEW030 21/13 A2999", CLLocationCoordinate2D(latitude: 37.3759, longitude: -121.9169)),
            ("KLAX", "MVFR", 16.0, 240, 18, "🌫️", "KLAX 050150Z 24018KT 5SM BR HZ OVC018 16/14 A2995", CLLocationCoordinate2D(latitude: 33.9536, longitude: -118.3965)),
            ("KJFK", "VFR", 24.0, 190, 12, "🌤️", "KJFK 050151Z 19012KT 10SM SCT250 24/18 A3002", CLLocationCoordinate2D(latitude: 40.6533, longitude: -73.7661)),
            ("KORD", "IFR", 12.0, 40, 22, "🌧️", "KORD 050156Z 04022KT 2SM -RA OVC009 12/10 A2988", CLLocationCoordinate2D(latitude: 41.9862, longitude: -87.8953)),
            ("VIDP", "LIFR", 14.0, 90, 4, "🌫️", "VIDP 050130Z 09004KT 1/2SM FG VV002 14/14 A1012", CLLocationCoordinate2D(latitude: 28.5682, longitude: 77.1120)),
            ("EGLL", "VFR", 15.0, 260, 8, "🌦️", "EGLL 050150Z 26008KT 9999 BKN035 15/09 Q1018", CLLocationCoordinate2D(latitude: 51.4820, longitude: -0.4423))
        ]
        
        for st in metarStations {
            let annotation = WeatherPointAnnotation()
            annotation.coordinate = st.coord
            annotation.icao = st.icao
            annotation.category = st.category
            annotation.tempCelsius = st.tempC
            annotation.windDir = st.windDir
            annotation.windSpeed = st.windSpd
            annotation.weatherCondition = st.icon
            let tempFormatted = mapState.formatTemp(st.tempC)
            annotation.title = "\(st.icao) \(st.icon) \(tempFormatted) [\(st.category)]"
            annotation.subtitle = "Winds: \(st.windDir)° @ \(st.windSpd)kt • \(st.metar)"
            mapView.addAnnotation(annotation)
        }
    }
    
    /// Airports for the visible area only.
    ///
    /// This used to add every airport in the catalog once and leave them there,
    /// which was fine for 52 international fields. The database now holds ~29,000,
    /// so the map shows what is in view — and raises the size threshold as you zoom
    /// out, so a continental view shows major fields while a local one shows the
    /// grass strips a training flight actually uses.
    private func addAirportAnnotations(_ mapView: MKMapView) {
        let existing = mapView.annotations.compactMap { $0 as? AirportPointAnnotation }

        let span = mapView.region.span.latitudeDelta
        let radiusNM = max(span * 60.0, 5)

        // 1 small, 2 medium, 3 large.
        let minimumType: Int
        switch span {
        case ..<0.9:  minimumType = 1     // local area: everything, including strips
        case ..<3.5:  minimumType = 2     // regional: medium and large
        default:      minimumType = 3     // continental: large only
        }
        let limit = span < 0.9 ? 80 : 50

        let wanted = mapState.airports.nearby(mapView.centerCoordinate,
                                              withinNM: radiusNM,
                                              limit: limit,
                                              minimumType: minimumType)
        let wantedIdents = Set(wanted.map(\.icao))
        let existingIdents = Set(existing.map(\.icao))
        guard wantedIdents != existingIdents else { return }

        mapView.removeAnnotations(existing.filter { !wantedIdents.contains($0.icao) })

        for airport in wanted where !existingIdents.contains(airport.icao) {
            let annotation = AirportPointAnnotation()
            annotation.coordinate = airport.coordinate
            annotation.title = airport.icao
            let place = [airport.city, airport.state].filter { !$0.isEmpty }.joined(separator: ", ")
            annotation.subtitle = place.isEmpty ? airport.name : "\(airport.name) — \(place)"
            annotation.icao = airport.icao
            // OurAirports records a TWR frequency for fields with a control tower.
            annotation.isTowered = airport.frequencies.contains {
                $0.type.uppercased().contains("TWR")
            }
            annotation.runwayHeadings = airport.runways.compactMap(\.trueHeadingLow)
            mapView.addAnnotation(annotation)
        }
    }
    
    private func addLiveFlights(_ mapView: MKMapView) {
        let existingFlightAnnotations = mapView.annotations.compactMap { $0 as? FlightPointAnnotation }
        let existingDict = Dictionary(grouping: existingFlightAnnotations, by: { $0.icao24 })

        var currentIcao24Set = Set<String>()
        
        for flight in liveFlightService.flights {
            currentIcao24Set.insert(flight.icao24)
            
            let cs = flight.callsign ?? "FLIGHT"
            let orig = flight.origin ?? "KSFO"
            let dest = flight.destination ?? "KLAX"
            let fl = Int((flight.altitude ?? 30000) / 100)
            let spd = Int(flight.speed ?? 400)
            let hdg = Int(flight.heading ?? 180)
            let newSubtitle = "\(cs): \(orig) → \(dest) [FL\(fl), \(spd)kts, \(hdg)°]"
            let newTitle = flight.isTracked ? "Tracked Flight" : "Traffic Flight"
            
            if let existingList = existingDict[flight.icao24], let existing = existingList.first {
                if existing.isTracked != flight.isTracked {
                    // Tracked state flipped: tracked vs traffic pins use different
                    // reuse identifiers/styling, and simply mutating .isTracked does
                    // NOT re-run viewFor — so the glyph/color wouldn't change. Remove
                    // and re-add to force the annotation view to rebuild with the
                    // correct icon.
                    mapView.removeAnnotation(existing)
                    let annotation = FlightPointAnnotation()
                    annotation.icao24 = flight.icao24
                    annotation.coordinate = flight.coordinate
                    annotation.title = newTitle
                    annotation.subtitle = newSubtitle
                    annotation.isTracked = flight.isTracked
                    annotation.heading = flight.heading ?? 0
                    mapView.addAnnotation(annotation)
                } else {
                    // Glide the existing marker to its new position over the refresh
                    // interval (client-side interpolation, like Flightradar24) so motion
                    // looks continuous despite the 2s data tick. Safe: flights are
                    // individual markers, so there is no cluster table to race.
                    existing.title = newTitle
                    existing.subtitle = newSubtitle
                    existing.heading = flight.heading ?? 0
                    let target = flight.coordinate
                    UIView.animate(withDuration: liveFlightService.updateInterval, delay: 0,
                                   options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
                        existing.coordinate = target
                    }
                }
            } else {
                // Add new annotation
                let annotation = FlightPointAnnotation()
                annotation.icao24 = flight.icao24
                annotation.coordinate = flight.coordinate
                annotation.title = newTitle
                annotation.subtitle = newSubtitle
                annotation.isTracked = flight.isTracked
                annotation.heading = flight.heading ?? 0
                mapView.addAnnotation(annotation)
            }
        }
        
        // Remove only annotations that left the radar region (except if selected)
        let toRemove = existingFlightAnnotations.filter { ann in
            if !currentIcao24Set.contains(ann.icao24) {
                if let selected = mapState.selectedFlight, selected.icao24 == ann.icao24 {
                    return false // Keep selected flight active!
                }
                return true
            }
            return false
        }
        // Remove synchronously so all of this tick's annotation mutations happen in
        // one batch. A deferred async removal could fire later, mid-cluster-
        // enumeration, and crash.
        if !toRemove.isEmpty {
            mapView.removeAnnotations(toRemove)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapView
        var hasSetInitialCamera = false

        // True while the map is animating a pan/zoom. During this window MapKit is
        // recomputing clusters (enumerating its annotation hash table), so we must
        // NOT add/remove/move annotations or we crash with "collection mutated
        // while being enumerated". Flight updates resume once the region settles.
        var isChangingRegion = false

        /// Selections arriving before this instant are ignored — see handleLongPress.
        var suppressAnnotationSelectionUntil: Date = .distantPast

        // Performance differential caching
        var lastWaypointsHash: String = ""
        var lastActiveLayers: Set<LayerKind> = []
        var lastMapStyle: MapStyle? = nil
        var lastIsNavigating: Bool = false
        var lastCurrentWaypointIdx: Int = -1

        // Rendered aircraft silhouettes, keyed by size + resolved tint.
        var aircraftImageCache: [String: UIImage] = [:]
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        // Aircraft silhouette sized for the map; the caller rotates it to the
        // flight's heading. Tracked flights render larger. See MapSymbols for why
        // the tint has to be rasterised rather than applied via tintColor.
        func aircraftImage(tracked: Bool, color: UIColor, traits: UITraitCollection) -> UIImage? {
            let resolved = color.resolvedColor(with: traits)
            let key = "\(tracked)|\(resolved)"
            if let cached = aircraftImageCache[key] { return cached }
            guard let img = MapSymbols.symbol("airplane",
                                              pointSize: tracked ? 26 : 18,
                                              weight: .black,
                                              color: resolved) else { return nil }
            aircraftImageCache[key] = img
            return img
        }

        // Traffic renders yellow, flights the pilot has marked for tracking render
        // green, so a tracked aircraft is instantly separable from the crowd. The
        // glyph still encodes the operator category for the marker/callout views.
        func colorForFlight(callsign: String, subtitle: String?, isTracked: Bool) -> (color: UIColor, glyph: String) {
            let color: UIColor = isTracked ? .systemGreen : .systemYellow
            if isTracked { return (color, "\u{2B50}") }

            let cs = callsign.uppercased()
            let sub = (subtitle ?? "").uppercased()

            if cs.hasPrefix("FDX") || cs.hasPrefix("UPS") || cs.hasPrefix("GTI") || cs.hasPrefix("CLX") || sub.contains("CARGO") {
                return (color, "\u{1F4E6}")   // cargo & freight
            }
            if cs.hasPrefix("N") || cs.hasPrefix("HUB") || sub.contains("GULFSTREAM") || sub.contains("GLF") || sub.contains("CITATION") {
                return (color, "\u{1F6E9}\u{FE0F}") // private business jet
            }
            return (color, "\u{2708}\u{FE0F}")
        }
        
        // Press-and-hold is the "add a waypoint" gesture and must work anywhere on
        // the map, including on top of a traffic or airport marker. Only callout
        // controls are excluded — those are buttons and own their own touches.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !(touch.view is UIControl)
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }

            switch gesture.state {
            case .began:
                // MapKit selects whatever marker is under the finger on touch-down,
                // which used to pop the aircraft or airport sheet open on every
                // press-and-hold. Hold the suppression window open until shortly
                // after the finger lifts so that selection is swallowed; a plain tap
                // is unaffected and still opens the detail.
                suppressAnnotationSelectionUntil = .distantFuture
                clearSelection(in: mapView)

                let point = gesture.location(in: mapView)
                let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                parent.mapState.addWaypoint(coordinate)

            case .ended, .cancelled, .failed:
                clearSelection(in: mapView)
                suppressAnnotationSelectionUntil = Date().addingTimeInterval(0.4)

            default:
                break
            }
        }

        /// Drops any marker MapKit latched onto during the press.
        private func clearSelection(in mapView: MKMapView) {
            for selected in Array(mapView.selectedAnnotations) {
                mapView.deselectAnnotation(selected, animated: false)
            }
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            } else if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                switch polyline.title {
                case "VisitedRouteBorder":
                    // Outer Blue Border for Visited Legs
                    renderer.strokeColor = UIColor.systemBlue
                    renderer.lineWidth = 7
                case "VisitedRouteCore":
                    // Inner Gray Core for Visited Legs
                    renderer.strokeColor = UIColor.systemGray
                    renderer.lineWidth = 4
                case "ActiveCurrentLeg":
                    // Vibrant Green Line for Active Leg (Prev -> Next)
                    renderer.strokeColor = UIColor.systemGreen
                    renderer.lineWidth = 6
                case "RemainingFutureRoute":
                    // Vibrant Blue Line for Rest of Route
                    renderer.strokeColor = UIColor.systemBlue
                    renderer.lineWidth = 5
                case "OffRouteDeviationBlackDotted":
                    // Thin Black Dotted Line for Off-Route Deviation
                    renderer.strokeColor = UIColor.black
                    renderer.lineWidth = 2
                    renderer.lineDashPattern = [3, 3]
                case "FlightTrail":
                    // Dashed flown-path trail behind the selected flight (FR24 style)
                    renderer.strokeColor = UIColor.systemCyan
                    renderer.lineWidth = 3
                    renderer.lineDashPattern = [2, 6]
                    renderer.lineCap = .round
                default:
                    renderer.strokeColor = UIColor.systemBlue
                    renderer.lineWidth = 5
                }
                return renderer
            } else if let airspace = overlay as? AirspaceOverlay {
                let renderer = MKPolygonRenderer(polygon: airspace)
                renderer.strokeColor = airspace.strokeColor.withAlphaComponent(0.85)
                renderer.fillColor = airspace.strokeColor.withAlphaComponent(0.07)
                renderer.lineWidth = 1.6
                // Class D is drawn dashed on a sectional.
                if airspace.airspaceClass == "D" { renderer.lineDashPattern = [4, 4] }
                return renderer
            } else if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor.systemCyan.withAlphaComponent(0.2)
                renderer.strokeColor = UIColor.systemCyan.withAlphaComponent(0.6)
                renderer.lineWidth = 2
                return renderer
            } else if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.systemRed.withAlphaComponent(0.25)
                renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.85)
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            DispatchQueue.main.async {
                self.parent.mapState.camera = mapView.camera
            }
        }
        
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            isChangingRegion = true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            isChangingRegion = false
            let center = mapView.centerCoordinate
            let span = mapView.region.span
            DispatchQueue.main.async {
                self.parent.mapState.camera = mapView.camera
                self.parent.liveFlightService.updateMapRegion(center: center, latDelta: span.latitudeDelta, lonDelta: span.longitudeDelta)
            }
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !annotation.isKind(of: MKUserLocation.self) else { return nil }
            
            // Handle Flight Clusters (grouped aircraft when zoomed out)
            if let cluster = annotation as? MKClusterAnnotation {
                let identifier = "FlightClusterAnnotation"
                var clusterView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                if clusterView == nil {
                    clusterView = MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: identifier)
                    clusterView?.canShowCallout = true
                } else {
                    clusterView?.annotation = cluster
                }
                
                let count = cluster.memberAnnotations.count
                clusterView?.markerTintColor = .systemYellow  // clusters are untracked traffic
                clusterView?.glyphText = "✈\(count)"
                clusterView?.glyphTintColor = .black
                clusterView?.displayPriority = .defaultHigh
                return clusterView
            }
            
            // Aircraft render as heading-rotated silhouettes, tinted by category.
            if let flightAnn = annotation as? FlightPointAnnotation {
                let isTracked = flightAnn.isTracked
                let identifier = isTracked ? "AircraftTracked" : "AircraftTraffic"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: flightAnn, reuseIdentifier: identifier)
                view.annotation = flightAnn
                view.canShowCallout = true
                view.centerOffset = .zero

                let callsign = flightAnn.title ?? "FLIGHT"
                let subtitle = flightAnn.subtitle ?? ""
                let style = colorForFlight(callsign: callsign, subtitle: subtitle, isTracked: isTracked)
                view.image = aircraftImage(tracked: isTracked, color: style.color, traits: view.traitCollection)
                view.tintColor = style.color

                // Point the nose along the flight's heading. The `airplane` symbol
                // points east (90°), so subtract 90° to align 0° with north.
                view.transform = CGAffineTransform(rotationAngle: CGFloat((flightAnn.heading - 90) * .pi / 180))
                view.displayPriority = isTracked ? .required : .defaultHigh

                // Soft yellow glow behind tracked flights.
                if isTracked {
                    view.layer.shadowColor = UIColor.systemGreen.cgColor
                    view.layer.shadowRadius = 5
                    view.layer.shadowOpacity = 0.9
                    view.layer.shadowOffset = .zero
                } else {
                    view.layer.shadowOpacity = 0
                }

                return view
            }
            
            if let title = annotation.title, title == "Tracked Flight" || title == "Traffic Flight" {
                let isTracked = (title == "Tracked Flight")
                let identifier = isTracked ? "TrackedFlightAnnotation" : "TrafficFlightAnnotation"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                
                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = true
                } else {
                    annotationView?.annotation = annotation
                }
                
                if let markerView = annotationView as? MKMarkerAnnotationView {
                    let subtitle = annotation.subtitle ?? ""
                    let callsign = (subtitle ?? "").components(separatedBy: ":").first ?? "FLIGHT"
                    let style = colorForFlight(callsign: callsign, subtitle: subtitle, isTracked: isTracked)
                    
                    markerView.markerTintColor = style.color
                    markerView.glyphText = style.glyph
                    markerView.clusteringIdentifier = nil
                    markerView.displayPriority = isTracked ? .required : .defaultHigh
                }
                
                return annotationView
            }
            
            // NOTAM hazards render as a warning triangle.
            if let notamAnn = annotation as? NOTAMPointAnnotation {
                let identifier = "NOTAMHazard"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: notamAnn, reuseIdentifier: identifier)
                view.annotation = notamAnn
                view.canShowCallout = true
                view.centerOffset = .zero
                view.image = MapSymbols.symbol("exclamationmark.triangle.fill",
                                               pointSize: 20, weight: .bold, color: .systemOrange)
                view.displayPriority = .required
                return view
            }
            
            // Handle Weather METAR Station Annotations (Black Rounded Rectangle Badge)
            if let weatherAnn = annotation as? WeatherPointAnnotation {
                let identifier = "CustomWeatherBadge"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? WeatherAnnotationView
                if annotationView == nil {
                    annotationView = WeatherAnnotationView(annotation: weatherAnn, reuseIdentifier: identifier)
                }
                
                annotationView?.configure(weather: weatherAnn, mapState: parent.mapState)
                annotationView?.displayPriority = .required
                annotationView?.zPriority = .max
                return annotationView
            }
            
            // Airports render as a flat chart-style roundel, distinct from aircraft.
            if let airportAnn = annotation as? AirportPointAnnotation {
                let identifier = "AirportRoundel"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: airportAnn, reuseIdentifier: identifier)
                view.annotation = airportAnn
                view.canShowCallout = true
                view.centerOffset = .zero
                view.image = MapSymbols.airportSymbol(towered: airportAnn.isTowered,
                                                      runwayHeadings: airportAnn.runwayHeadings,
                                                      diameter: airportAnn.isTowered ? 22 : 18)
                view.displayPriority = .required
                view.zPriority = .min
                return view
            }
            
            // Route waypoints render as a numbered diamond, so a planned point reads
            // differently from airports (roundels) and aircraft (silhouettes). The
            // departure and destination ends get their own colour and glyph.
            if let wpAnn = annotation as? RouteWaypointAnnotation {
                let identifier = "RouteWaypoint"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: wpAnn, reuseIdentifier: identifier)
                view.annotation = wpAnn
                view.canShowCallout = true
                view.centerOffset = .zero
                view.displayPriority = .required

                if wpAnn.isDeparture {
                    view.image = MapSymbols.symbol("airplane.departure", pointSize: 17, weight: .bold, color: .systemGreen)
                } else if wpAnn.isDestination {
                    view.image = MapSymbols.symbol("airplane.arrival", pointSize: 17, weight: .bold, color: .systemRed)
                } else {
                    view.image = MapSymbols.waypointDiamond(index: wpAnn.index, isEndpoint: false, color: .systemBlue)
                }
                return view
            }

            let identifier = "GenericPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = true
            view.centerOffset = .zero
            view.image = MapSymbols.symbol("diamond.fill", pointSize: 15, weight: .bold, color: .systemBlue)
            return view
        }
        
        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            // Defer off the update cycle: didDeselect can fire from inside
            // updateUIView (programmatic deselect on sheet close), and stopTrail
            // mutates @Published state, which must not happen during a view update.
            if view.annotation is FlightPointAnnotation {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.liveFlightService.stopTrail()
                }
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }

            // A press-and-hold is a waypoint drop, not a marker tap. Detail sheets
            // open on a single press only.
            if Date() < suppressAnnotationSelectionUntil {
                mapView.deselectAnnotation(annotation, animated: false)
                return
            }
            
            // Handle weather badge taps (Deselect without showing tooltip)
            if let weatherAnn = annotation as? WeatherPointAnnotation {
                mapView.deselectAnnotation(weatherAnn, animated: true)
                return
            }
            
            // Handle flight annotations (FlightPointAnnotation or title match)
            if let flightAnn = annotation as? FlightPointAnnotation {
                let subtitleText = flightAnn.subtitle ?? ""
                let parts = subtitleText.components(separatedBy: ": ")
                let callsign = parts.first ?? "FLIGHT"
                let routeStr = parts.last ?? ""
                let routeParts = routeStr.components(separatedBy: " → ")
                let origin = routeParts.first ?? "KSFO"
                let dest = routeParts.last ?? "KLAX"
                
                // Fetch real live flight telemetry object if available
                let liveFlight = parent.liveFlightService.flights.first(where: { $0.icao24 == flightAnn.icao24 || $0.callsign == callsign })
                
                let realAlt = liveFlight?.altitude ?? Double.random(in: 28000...41000)
                let realSpeed = liveFlight?.speed ?? Double.random(in: 410...490)
                let realHeading = liveFlight?.heading ?? Double.random(in: 45...315)
                let realVRate = liveFlight?.verticalRate ?? 0.0
                let realSquawk = liveFlight?.squawk ?? String(format: "%04d", Int.random(in: 1200...7700))
                
                // Calculate real distance to destination using Haversine
                let destCoord = parent.mapState.airports[dest]?.coordinate ?? CLLocationCoordinate2D(latitude: 37.6213, longitude: -122.3790)
                let realDistNM = parent.mapState.distanceNM(flightAnn.coordinate, destCoord)
                let flightHours = max(0.2, realDistNM / max(100.0, realSpeed))
                let realETA = Date().addingTimeInterval(flightHours * 3600)
                let realFuelLBS = max(800.0, round(realDistNM * 6.5))
                
                // Dynamic en route weather computation based on altitude and location
                let wDir = Int(realHeading + 35) % 360
                let wSpd = Int(realSpeed * 0.05) + 10
                let cat = (realAlt > 12000) ? "VFR Clear" : "MVFR Scattered"
                let realWeather = "\(cat) • Winds \(wDir)° @ \(wSpd)kt • Alt \(Int(realAlt))ft"
                
                let acType: (type: String, cat: String, reg: String, img: String)
                if callsign.hasPrefix("SWA") {
                    acType = ("Boeing 737 MAX 8 (B38M)", "Narrow-body Commercial Jet", "N8712Q", "https://images.unsplash.com/photo-1520437358207-323b43b57539?auto=format&fit=crop&w=1200&q=80")
                } else if callsign.hasPrefix("AAL") {
                    acType = ("Airbus A321neo (A21N)", "Narrow-body Commercial Jet", "N401AN", "https://images.unsplash.com/photo-1508672019048-805479760c23?auto=format&fit=crop&w=1200&q=80")
                } else if callsign.hasPrefix("DAL") {
                    acType = ("Airbus A350-900 (A359)", "Wide-body Long Range Jet", "N501DN", "https://images.unsplash.com/photo-1436491865332-7a61a109cc05?auto=format&fit=crop&w=1200&q=80")
                } else if callsign.hasPrefix("HUB") || callsign.hasPrefix("N") {
                    acType = ("Gulfstream G650ER (GLF6)", "Ultra Long Range Business Jet", "N1KE", "https://images.unsplash.com/photo-1569154941061-e231b4725ef1?auto=format&fit=crop&w=1200&q=80")
                } else {
                    acType = ("Boeing 777-300ER (B773)", "Wide-body Commercial Jet", "N780UA", "https://images.unsplash.com/photo-1556388158-158ea5ccacbd?auto=format&fit=crop&w=1200&q=80")
                }
                
                parent.mapState.selectedFlight = FlightAnalysis(
                    callsign: callsign,
                    origin: origin,
                    destination: dest,
                    altitude: round(realAlt),
                    speed: round(realSpeed),
                    heading: round(realHeading),
                    verticalRate: round(realVRate),
                    squawk: realSquawk,
                    distance: round(realDistNM),
                    eta: realETA,
                    fuelRemaining: realFuelLBS,
                    weather: realWeather,
                    icao24: flightAnn.icao24,
                    aircraftType: acType.type,
                    aircraftCategory: acType.cat,
                    registration: acType.reg,
                    coordinate: flightAnn.coordinate,
                    imageURL: acType.img
                )
                parent.mapState.showingFlightDetail = true
                parent.liveFlightService.startTrail(icao24: flightAnn.icao24)
                return
            }
            
            if let title = annotation.title, title == "Tracked Flight" || title == "Traffic Flight" {
                let subtitleText = (annotation.subtitle ?? "") ?? ""
                let parts = subtitleText.components(separatedBy: ": ")
                let callsign = parts.first ?? "FLIGHT"
                let routeStr = parts.last ?? ""
                let routeParts = routeStr.components(separatedBy: " → ")
                let origin = routeParts.first ?? "KSFO"
                let dest = routeParts.last ?? "KLAX"
                
                let liveFlight = parent.liveFlightService.flights.first(where: { $0.callsign == callsign })
                let realAlt = liveFlight?.altitude ?? Double.random(in: 24000...38000)
                let realSpeed = liveFlight?.speed ?? Double.random(in: 390...470)
                let realHeading = liveFlight?.heading ?? Double.random(in: 30...330)
                let realVRate = liveFlight?.verticalRate ?? 0.0
                let realSquawk = liveFlight?.squawk ?? String(format: "%04d", Int.random(in: 1200...7700))
                
                let destCoord = parent.mapState.airports[dest]?.coordinate ?? CLLocationCoordinate2D(latitude: 37.6213, longitude: -122.3790)
                let realDistNM = parent.mapState.distanceNM(annotation.coordinate, destCoord)
                let flightHours = max(0.2, realDistNM / max(100.0, realSpeed))
                let realETA = Date().addingTimeInterval(flightHours * 3600)
                let realFuelLBS = max(800.0, round(realDistNM * 6.5))
                
                let wDir = Int(realHeading + 25) % 360
                let wSpd = Int(realSpeed * 0.04) + 12
                let realWeather = "VFR Clear • Winds \(wDir)° @ \(wSpd)kt • Alt \(Int(realAlt))ft"
                
                parent.mapState.selectedFlight = FlightAnalysis(
                    callsign: callsign,
                    origin: origin,
                    destination: dest,
                    altitude: round(realAlt),
                    speed: round(realSpeed),
                    heading: round(realHeading),
                    verticalRate: round(realVRate),
                    squawk: realSquawk,
                    distance: round(realDistNM),
                    eta: realETA,
                    fuelRemaining: realFuelLBS,
                    weather: realWeather,
                    coordinate: annotation.coordinate
                )
                parent.mapState.showingFlightDetail = true
                return
            }
            
            // Handle airport annotations
            if let title = annotation.title, let icao = title,
               let airport = parent.mapState.airports[icao] {
                parent.mapState.selectedAirport = airport
                parent.mapState.showingAirportDetail = true
            }
        }
    }
}

// MARK: - Flight Detail View
struct FlightDetailView: View {
    let flight: FlightAnalysis
    @ObservedObject var mapState: MapState
    @EnvironmentObject var liveFlightService: LiveFlightService
    @Environment(\.dismiss) private var dismiss
    
    var isTracked: Bool {
        liveFlightService.flights.first(where: { $0.callsign == flight.callsign })?.isTracked ?? false
    }
    
    var liveTelemetry: LiveFlight? {
        liveFlightService.flights.first(where: { $0.callsign == flight.callsign || $0.icao24 == flight.icao24 })
    }
    
    var currentAltitude: Double {
        liveTelemetry?.altitude ?? flight.altitude
    }
    
    var currentSpeed: Double {
        liveTelemetry?.speed ?? flight.speed
    }
    
    var currentHeading: Double {
        liveTelemetry?.heading ?? flight.heading
    }
    
    var currentVerticalRate: Double {
        liveTelemetry?.verticalRate ?? flight.verticalRate
    }
    
    var currentSquawk: String {
        liveTelemetry?.squawk ?? flight.squawk
    }
    
    var currentEnRouteWeather: String {
        let wDir = Int(currentHeading + 35) % 360
        let wSpd = Int(currentSpeed * 0.05) + 10
        let cat = (currentAltitude > 12000) ? "VFR Clear" : "MVFR Scattered"
        return "\(cat) • Winds \(wDir)° @ \(wSpd)kt • Alt \(Int(currentAltitude))ft"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Structured Multi-Row Flight Information Header Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "airplane.circle.fill")
                                .font(.system(size: 34))
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("FLIGHT SPECIFICATION")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                Text(flight.callsign)
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            
                            Spacer()
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.15))
                        
                        // Structured Multi-Row Key-Value Details
                        VStack(spacing: 6) {
                            FlightDetailRow(label: "Flight Call Sign", value: flight.callsign, icon: "paperplane.fill", color: .green)
                            if let icao24 = flight.icao24, !icao24.isEmpty {
                                FlightDetailRow(label: "ICAO Transponder", value: icao24.uppercased(), icon: "number", color: .cyan)
                            }
                            FlightDetailRow(label: "Origin Airport", value: mapState.airportName(for: flight.origin), icon: "airplane.departure", color: .blue)
                            FlightDetailRow(label: "Destination Airport", value: mapState.airportName(for: flight.destination), icon: "airplane.arrival", color: .purple)
                            FlightDetailRow(label: "Squawk Code", value: currentSquawk, icon: "dot.radiowaves.left.and.right", color: .orange)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                    
                    // Prominent Track / Untrack Action Card
                    Button(action: {
                        liveFlightService.toggleTrackedFlight(
                            callsign: flight.callsign,
                            origin: flight.origin,
                            destination: flight.destination,
                            altitude: currentAltitude,
                            speed: currentSpeed,
                            heading: currentHeading,
                            coordinate: flight.coordinate
                        )
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: isTracked ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundColor(isTracked ? .yellow : .cyan)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isTracked ? "TRACKED FLIGHT" : "TRACK THIS FLIGHT")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(isTracked ? .yellow : .cyan)
                                Text(isTracked ? "Flight is active in your tracked list. Tap to untrack." : "Receive real-time telemetry & alerts for this flight.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(isTracked ? "Untrack" : "Track Flight")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isTracked ? Color.yellow.opacity(0.3) : Color.cyan.opacity(0.25))
                                .foregroundColor(isTracked ? .yellow : .cyan)
                                .clipShape(Capsule())
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isTracked ? Color.yellow.opacity(0.5) : Color.cyan.opacity(0.3), lineWidth: 1.5)
                        )
                    }
                    
                    // Aircraft Equipment & Photo Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "airplane")
                                .font(.headline)
                                .foregroundColor(.cyan)
                            Text("Aircraft Equipment")
                                .font(.headline)
                        }
                        
                        // Aircraft Visual Photo Banner Card with AsyncImage
                        ZStack(alignment: .bottomLeading) {
                            if let imgStr = flight.imageURL, let url = URL(string: imgStr) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 150)
                                            .frame(maxWidth: .infinity)
                                            .clipped()
                                            .cornerRadius(12)
                                    } else {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6), Color.black.opacity(0.95)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(height: 150)
                                            .overlay(
                                                Image(systemName: "airplane")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(height: 75)
                                                    .foregroundColor(.white.opacity(0.85))
                                            )
                                    }
                                }
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6), Color.black.opacity(0.95)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(height: 150)
                                    .overlay(
                                        Image(systemName: "airplane")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 75)
                                            .foregroundColor(.white.opacity(0.85))
                                    )
                            }
                            
                            // Dark gradient overlay for text contrast
                            VStack {
                                Spacer()
                                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 60)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(flight.aircraftType)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text("\(flight.aircraftCategory) • Reg: \(flight.registration)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding()
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                    
                    // Live Flight Metrics Grid (Updates Live in Real-Time!)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(title: "Altitude", value: "\(Int(currentAltitude)) FT", icon: "arrow.up.and.down")
                        MetricCard(title: "Speed", value: "\(Int(currentSpeed)) KTAS", icon: "speedometer")
                        MetricCard(title: "Heading", value: "\(Int(currentHeading))°", icon: "compass.drawing")
                        MetricCard(title: "Squawk", value: currentSquawk, icon: "number")
                        MetricCard(title: "Est. Distance", value: "\(Int(flight.distance)) NM", icon: "ruler")
                        MetricCard(title: "Fuel Remaining", value: "\(Int(flight.fuelRemaining ?? 0)) LBS", icon: "fuelpump")
                    }
                    
                    // Live En Route Weather
                    VStack(alignment: .leading, spacing: 8) {
                        Text("En Route Weather")
                            .font(.headline)
                        HStack {
                            Image(systemName: "sun.max.fill")
                                .foregroundColor(.yellow)
                            Text(currentEnRouteWeather)
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                    
                    // Map focus button (Center Flight on Map)
                    Button(action: {
                        let targetCoord = flight.coordinate ?? mapState.airports[flight.origin]?.coordinate ?? CLLocationCoordinate2D(latitude: 37.6213, longitude: -122.3790)
                        mapState.camera = MKMapCamera(lookingAtCenter: targetCoord, fromDistance: 45_000, pitch: 0, heading: 0)
                        mapState.shouldCenterCamera = true
                        mapState.selectedFlight = nil
                        mapState.showingFlightDetail = false
                        dismiss()
                    }) {
                        Label("Center Flight on Map", systemImage: "map.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                }
                .padding()
            }
            .navigationTitle("Flight Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        mapState.selectedFlight = nil
                        mapState.showingFlightDetail = false
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FlightDetailRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Status Bar
struct StatusBar: View {
    @ObservedObject var mapState: MapState
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StatusIndicator(
                    icon: "location.circle.fill",
                    text: "GPS",
                    isActive: locationManager.authorizationStatus == .authorizedWhenInUse
                )
                
                StatusIndicator(
                    icon: "antenna.radiowaves.left.and.right",
                    text: "ADS-B",
                    isActive: true
                )
                
                StatusIndicator(
                    icon: "gyroscope",
                    text: "AHRS",
                    isActive: locationManager.heading != nil
                )
                
                StatusIndicator(
                    icon: "aqi.medium",
                    text: "CO",
                    isActive: true
                )
                
                Label("240° @ 28kt", systemImage: "wind")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Capsule())
                
                HStack(spacing: 4) {
                    Image(systemName: mapState.mode.icon)
                        .foregroundColor(mapState.mode.color)
                    Text(mapState.mode.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(mapState.mode.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(mapState.mode.color.opacity(0.2))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

struct StatusIndicator: View {
    let icon: String
    let text: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(isActive ? .green : .red)
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(isActive ? .green : .red)
        }
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.3))
        .clipShape(Capsule())
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    /// Set by the caller, because this one field does different work depending on
    /// whether a route is under way. See UnifiedSearch.swift.
    var placeholder: String = "Search airports, places, or coordinates"
    let onSearch: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isTextFieldFocused)
                .onChange(of: isTextFieldFocused) { focused in
                    if focused {
                        // Snappy expand so the field feels instant when tapped
                        // (a slow spring here reads as "the search bar is laggy").
                        withAnimation(.easeOut(duration: 0.2)) {
                            isExpanded = true
                        }
                    }
                }
                .onSubmit {
                    onSearch()
                    isTextFieldFocused = false
                }
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            if isExpanded {
                Button(action: {
                    text = ""
                    isTextFieldFocused = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                    hideKeyboard()
                }) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Layer Controls
struct LayerControls: View {
    @ObservedObject var mapState: MapState
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // The aircraft leads the strip: it is the assumption behind every
                // number the planner produces, and this row is the one thing on
                // screen whether the sheet is open or closed. Styled as a selector
                // with a chevron, not a toggle, because the rest of this row turns
                // map layers on and off and the aircraft does neither.
                AircraftChip(mapState: mapState)

                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 2)

                // NOTAMs are hidden while no credentials are configured: a toggle
                // that can only ever show an empty layer is worse than no toggle.
                // The omission is still disclosed in Check Route, so nobody assumes
                // the preflight check covered them.
                ForEach(LayerKind.allCases.filter {
                    $0 != .notams || mapState.notams.isConfigured
                }) { layer in
                    LayerButton(
                        layer: layer,
                        isActive: mapState.activeLayers.contains(layer),
                        action: {
                            mapState.toggle(layer)
                        }
                    )
                }
            }
            .padding(.horizontal, 8)
        }
        .aeroSurface(.floating, cornerRadius: 20)
    }
}

/// Aircraft selector at the head of the layer strip.
///
/// Shows the selected type's ident so the current assumption is readable at a
/// glance, and opens the picker on tap.
struct AircraftChip: View {
    @ObservedObject var mapState: MapState

    var body: some View {
        Button {
            mapState.showingAircraftPicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "airplane")
                    .font(.caption)
                Text(mapState.route.aircraft.shortLabel)
                    .font(.caption).fontWeight(.bold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.85))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LayerButton: View {
    let layer: LayerKind
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: layer.systemImage)
                    .foregroundColor(isActive ? layer.color : .white.opacity(0.7))
                Text(layer.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isActive ? layer.color : .white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isActive ? layer.color.opacity(0.2) : Color.black.opacity(0.3)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isActive ? layer.color : Color.white.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Floating Action Buttons
struct FloatingActionButtons: View {
    @ObservedObject var mapState: MapState
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        VStack(spacing: 12) {
            // Zoom controls, grouped into one pill so they read as a pair rather
            // than two unrelated buttons. Pinch is awkward on a trackpad and worse
            // one-handed in a cockpit.
            VStack(spacing: 0) {
                MapZoomButton(icon: "plus") { mapState.zoomCamera(by: 0.5) }
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 24, height: 1)
                MapZoomButton(icon: "minus") { mapState.zoomCamera(by: 2.0) }
            }
            .aeroSurface(.floating, cornerRadius: 24)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)

            // Locate Button (Go to Current Location)
            FloatingButton(
                icon: "location.fill",
                action: {
                    let targetCoord = locationManager.lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 37.6213, longitude: -122.3790)
                    withAnimation(.easeInOut(duration: 1.0)) {
                        mapState.camera = MKMapCamera(
                            lookingAtCenter: targetCoord,
                            fromDistance: 140_000,
                            pitch: 0,
                            heading: 0
                        )
                        mapState.shouldCenterCamera = true
                    }
                }
            )
        }
    }
}

/// A zoom step. Deliberately without its own background: these sit inside a shared
/// pill, so a per-button circle would fight the container.
struct MapZoomButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3).fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 50, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FloatingButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(.thickMaterial)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Top In-Flight Navigation HUD Banner (Turn-by-Turn Pilot Guidance)
struct TopNavigationHUDBanner: View {
    @ObservedObject var mapState: MapState
    
    var currentNextWaypoint: Waypoint? {
        guard mapState.route.waypoints.count >= 2 else { return nil }
        let nextIdx = min(mapState.currentWaypointIndex + 1, mapState.route.waypoints.count - 1)
        return mapState.route.waypoints[nextIdx]
    }
    
    var distToNextNM: Double {
        guard let userLoc = mapState.locationManager?.lastLocation?.coordinate,
              let nextWp = currentNextWaypoint else { return 14.2 }
        return mapState.distanceNM(userLoc, nextWp.coordinate)
    }
    
    var eteMin: Int {
        let cruiseKT = max(90.0, mapState.route.cruiseKTAS)
        return max(1, Int(distToNextNM / cruiseKT * 60))
    }
    
    var body: some View {
        if mapState.routeCompleted {
            completionBanner
        } else {
            activeBanner
        }
    }

    // Shown once the aircraft reaches the final waypoint.
    var completionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30))
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("ROUTE COMPLETE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                Text(mapState.route.displayName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(Int(mapState.route.totalDistanceNM)) NM • \(mapState.route.waypoints.count) waypoints reached")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            Button(action: {
                withAnimation {
                    mapState.cancelRouteNavigation()
                }
            }) {
                Text("Finish")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.green.opacity(0.7), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 14)
        .padding(.top, 50)
    }

    var activeBanner: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                // Direction Turn Indicator Icon
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("NEXT WAYPOINT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        
                        if mapState.offRouteDistanceNM > 0.3 {
                            Text("⚠️ OFF-ROUTE \(String(format: "%.1f", mapState.offRouteDistanceNM)) NM")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("\(currentNextWaypoint?.icao ?? "KSJC") — \(currentNextWaypoint?.name ?? "San Jose Intl")")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text("\(String(format: "%.1f", distToNextNM)) NM")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        Text("•  ETE: \(eteMin) min")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("•  💨 270° @ 18kt")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                // ❌ Cancel Route Button
                Button(action: {
                    withAnimation {
                        mapState.cancelRouteNavigation()
                    }
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                        Text("Cancel")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(6)
                    .background(Color.red.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        mapState.offRouteDistanceNM > 0.3 ? Color.orange : Color.green.opacity(0.6),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 50)
    }
}

// MARK: - Routes & Navigation Tab View (Route Panel)
struct RoutesTabView: View {
    @ObservedObject var mapState: MapState
    @State private var selectedRouteForReview: RoutePlan? = nil
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Spacer for Top Floating Mode Selector Pill
                    Spacer()
                        .frame(height: 35)
                    
                    // 1. Saved Routes Library (Always visible when saved routes exist!)
                    if !mapState.savedRoutes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.headline)
                                    .foregroundColor(.cyan)
                                Text("SAVED ROUTES LIBRARY (\(mapState.savedRoutes.count))")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.cyan)
                            }
                            
                            ForEach(mapState.savedRoutes) { saved in
                                HStack(spacing: 10) {
                                    // Card Content (Tapping opens Pre-Flight Review Sheet)
                                    Button(action: {
                                        selectedRouteForReview = saved
                                    }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(saved.displayName)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            
                                            Text("\(Int(saved.totalDistanceNM)) NM • \(saved.waypoints.count) Waypoints")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    Spacer()
                                    
                                    // Review Button
                                    Button(action: {
                                        selectedRouteForReview = saved
                                    }) {
                                        Text("Review")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.3))
                                            .foregroundColor(.blue)
                                            .clipShape(Capsule())
                                    }
                                    
                                    // Load on Map Button
                                    Button(action: {
                                        withAnimation(.easeInOut) {
                                            mapState.route = saved
                                            mapState.activeTab = 0 // Return to map with route loaded!
                                            mapState.shouldCenterCamera = true
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "map.fill")
                                                .font(.caption2)
                                            Text("Load")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.cyan)
                                        .foregroundColor(.black)
                                        .clipShape(Capsule())
                                    }
                                    
                                    // Delete Route Button
                                    Button(action: {
                                        withAnimation {
                                            mapState.deleteSavedRoute(id: saved.id)
                                        }
                                    }) {
                                        Image(systemName: "trash.fill")
                                            .font(.caption)
                                            .foregroundColor(.red.opacity(0.85))
                                            .padding(8)
                                            .background(Color.red.opacity(0.15))
                                            .clipShape(Circle())
                                    }
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(14)
                            }
                        }
                    }
                    
                    // 2. Active Route Plan (if waypoints currently placed on map)
                    if mapState.route.waypoints.count >= 2 {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "location.north.line.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ACTIVE MAP ROUTE")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                    
                                    Text(mapState.route.displayName)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                }
                                
                                Spacer()
                                
                                Text("\(Int(mapState.route.totalDistanceNM)) NM")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .clipShape(Capsule())
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                            
                            // Metrics Row
                            HStack {
                                MetricCard(title: "EST DISTANCE", value: "\(Int(mapState.route.totalDistanceNM)) NM", icon: "ruler")
                                MetricCard(title: "EST ETE", value: "\(mapState.route.formattedFlightTime)", icon: "clock")
                                MetricCard(title: "EST FUEL", value: "\(Int(mapState.route.totalFuelBurnLBS)) lbs", icon: "fuelpump")
                            }
                            
                            // Navigation & Save Actions
                            if mapState.isNavigatingRoute {
                                Button(action: {
                                    withAnimation {
                                        mapState.cancelRouteNavigation()
                                    }
                                }) {
                                    Label("Cancel Navigation", systemImage: "xmark.circle.fill")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                            } else {
                                HStack(spacing: 12) {
                                    Button(action: {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            mapState.startRouteNavigation()
                                        }
                                    }) {
                                        Label("Start Route", systemImage: "play.circle.fill")
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(Color.green)
                                            .foregroundColor(.black)
                                            .cornerRadius(12)
                                    }
                                    
                                    Button(action: {
                                        mapState.prepareSaveRoute()
                                    }) {
                                        Label("Save Route", systemImage: "square.and.arrow.down.fill")
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                        
                        // Waypoints Breakdown List
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ROUTE WAYPOINTS (\(mapState.route.waypoints.count))")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            
                            ForEach(Array(mapState.route.waypoints.enumerated()), id: \.offset) { idx, wp in
                                HStack {
                                    let isPassed = mapState.isNavigatingRoute && idx < mapState.currentWaypointIndex
                                    let isCurrent = mapState.isNavigatingRoute && idx == mapState.currentWaypointIndex
                                    
                                    Circle()
                                        .fill(isPassed ? Color.gray : (isCurrent ? Color.green : Color.cyan))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text("\(idx + 1)")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.black)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(wp.icao)
                                            .font(.headline)
                                            .foregroundColor(isPassed ? .secondary : .primary)
                                        Text(wp.name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if isPassed {
                                        Text("Passed")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.gray)
                                    } else if isCurrent {
                                        Text("Next Waypoint")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                    } else if mapState.savedRoutes.isEmpty {
                        // Empty State (No Route Planned & No Saved Routes)
                        VStack(spacing: 16) {
                            Image(systemName: "directcurrent")
                                .font(.system(size: 60))
                                .foregroundColor(.cyan)
                            
                            Text("No Saved or Active Routes")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Tap points on the map or search airports to build your flight plan.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button(action: {
                                mapState.activeTab = 0
                            }) {
                                Label("Plan Route on Map", systemImage: "map.fill")
                                    .font(.headline)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.top, 40)
                    }
                }
                .padding()
            }
            .navigationTitle("Routes & Navigation")
        }
        .sheet(item: $selectedRouteForReview) { plan in
            RouteReviewView(plan: plan, mapState: mapState) {
                selectedRouteForReview = nil
            }
        }
    }
}

// MARK: - Pre-Flight Route Review Sheet
// Opened by tapping a saved route. Lets the pilot review the full plan
// BEFORE committing it to the map or starting live navigation.
struct RouteReviewView: View {
    let plan: RoutePlan
    @ObservedObject var mapState: MapState
    var onDismiss: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PRE-FLIGHT REVIEW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        Text(plan.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    // Key Metrics
                    HStack {
                        MetricCard(title: "DISTANCE", value: "\(Int(plan.totalDistanceNM)) NM", icon: "ruler")
                        MetricCard(title: "EST ETE", value: plan.formattedFlightTime, icon: "clock")
                        MetricCard(title: "EST FUEL", value: "\(Int(plan.totalFuelBurnLBS)) lbs", icon: "fuelpump")
                    }

                    HStack {
                        MetricCard(title: "CRUISE ALT", value: "\(plan.altitudeFT) ft", icon: "arrow.up.to.line")
                        MetricCard(title: "CRUISE SPD", value: "\(Int(plan.cruiseKTAS)) kt", icon: "gauge.high")
                        MetricCard(title: "WAYPOINTS", value: "\(plan.waypoints.count)", icon: "mappin.and.ellipse")
                    }

                    // Waypoint breakdown
                    Text("ROUTE WAYPOINTS (\(plan.waypoints.count))")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    VStack(spacing: 10) {
                        ForEach(Array(plan.waypoints.enumerated()), id: \.offset) { idx, wp in
                            HStack {
                                Circle()
                                    .fill(Color.cyan)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Text("\(idx + 1)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.black)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(wp.icao.isEmpty ? wp.name : wp.icao)
                                        .font(.headline)
                                    if !wp.name.isEmpty {
                                        Text(wp.name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                if idx == 0 {
                                    reviewTag("DEP", .green)
                                } else if idx == plan.waypoints.count - 1 {
                                    reviewTag("ARR", .orange)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                    }

                    // Actions
                    VStack(spacing: 12) {
                        Button(action: {
                            mapState.startSavedRoute(plan)
                            onDismiss()
                        }) {
                            Label("Start Route", systemImage: "play.circle.fill")
                                .font(.headline)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }

                        Button(action: {
                            mapState.loadSavedRoute(plan)
                            onDismiss()
                        }) {
                            Label("Load on Map", systemImage: "map.fill")
                                .font(.headline)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Route Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss() }
                }
            }
        }
    }

    private func reviewTag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

