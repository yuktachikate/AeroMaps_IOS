import SwiftUI
import MapKit

struct BottomSheet: View {
    @ObservedObject var mapState: MapState
    /// The window's height, measured by the host rather than taken from
    /// UIScreen — under Split View or Stage Manager the app's window is not the
    /// screen, and UIScreen.main is deprecated for exactly that reason.
    var windowHeight: CGFloat = 800

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isExpanded = false

    private var layout: PlanningLayout {
        PlanningLayout(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    /// The side panel is always open: there is room for the map beside it, so
    /// collapsing it would hide the route for no gain.
    private var isOpen: Bool { layout.isSidePanel || isExpanded }
    
    /// Rounded on whichever edges face the map: the top for a bottom sheet, the
    /// trailing side for a panel sitting against the leading edge.
    private var surfaceShape: UnevenRoundedRectangle {
        layout.isSidePanel
            ? UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                     bottomTrailingRadius: 24, topTrailingRadius: 24,
                                     style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0,
                                     bottomTrailingRadius: 0, topTrailingRadius: 24,
                                     style: .continuous)
    }

    /// Route tools need two points. Saying so beats a row of dimmed buttons with no
    /// explanation — which is exactly how it read before.
    private var needsDestinationHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption)
                .foregroundColor(.cyan)
            Text("Add a destination to unlock generate, validate, profile and the briefing tools.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.cyan.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var searchResults: [Airport] {
        let query = mapState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !query.isEmpty else { return [] }
        
        let localMatches = mapState.airports.search(query, near: mapState.camera.centerCoordinate, limit: 12)
        
        var combined = mapState.liveSearchResults
        for localItem in localMatches {
            if !combined.contains(where: { $0.icao == localItem.icao || $0.name == localItem.name }) {
                combined.append(localItem)
            }
        }
        
        return combined.sorted(by: { $0.name < $1.name })
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // Drag handle, omitted on the side panel, which does not collapse.
            if !layout.isSidePanel {
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
            }
            }
            
            // 1. Search Bar (At top of bottom sheet, like Apple Maps)
            SearchBar(
                text: $mapState.searchText,
                isExpanded: $isExpanded,
                onSearch: { mapState.parseSearch() }
            )
            .padding(.horizontal, 14)
            
            // Route status, from the first dropped point through to in-flight.
            if !mapState.route.waypoints.isEmpty {
                ConfirmFlightPlanBanner(mapState: mapState, isExpanded: $isExpanded)
            }
            
            // Live Airport & Code Search Autocomplete Dropdown
            if !mapState.searchText.isEmpty {
                VStack(spacing: 4) {
                    if mapState.isSearchingLive && searchResults.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                            Text("Searching global airport database...")
                                .font(.subheadline)
                                .foregroundColor(.cyan)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    } else if searchResults.isEmpty {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            Text("No airports matching '\(mapState.searchText)'")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 4) {
                                ForEach(searchResults) { airport in
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.8)) {
                                            mapState.camera = MKMapCamera(
                                                lookingAtCenter: airport.coordinate,
                                                fromDistance: 45_000,
                                                pitch: 0,
                                                heading: 0
                                            )
                                            mapState.shouldCenterCamera = true
                                        }
                                        mapState.selectedAirport = airport
                                        mapState.showingAirportDetail = true
                                        mapState.searchText = ""
                                        hideKeyboard()
                                    }) {
                                        HStack(spacing: 12) {
                                            Text(airport.icao)
                                                .font(.headline)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue.opacity(0.5))
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(airport.name)
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.white)
             
                                                    .lineLimit(1)
                                                Text("\(airport.city), \(airport.state)")
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                        .frame(maxHeight: 220)
                    }
                }
            }
            
            // 2. Layer Control Pallets (Traffic, Radar, Airspace, FFM Risk)
            LayerControls(mapState: mapState)
                .padding(.horizontal, 14)
                .padding(.bottom, isOpen ? 0 : 24)
            
            // 3. The planning surface, in the order a route is actually worked:
            //    build it → refine and check it → see what it costs → set up the
            //    aircraft → reach for the secondary tools.
            if isOpen {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        Divider()
                            .background(Color.white.opacity(0.2))
                            .padding(.horizontal, 16)

                        // First, because the aircraft is the assumption every
                        // distance, time, altitude and fuel figure below rests on.
                        AircraftCard(mapState: mapState)
                            .padding(.horizontal, 14)

                        RouteBuilderView(mapState: mapState)
                            .padding(.horizontal, 14)

                        // Local flying first: the fields around you, one tap away.
                        NearbyAirportsStrip(mapState: mapState)
                            .padding(.horizontal, 14)

                        if mapState.route.waypoints.count >= 2 {
                            RouteRefineBar(mapState: mapState)
                                .padding(.horizontal, 14)

                            RouteTotalsView(mapState: mapState)
                                .padding(.horizontal, 14)
                        } else if !mapState.route.waypoints.isEmpty {
                            needsDestinationHint
                                .padding(.horizontal, 14)
                        }

                        SecondaryToolsView(mapState: mapState)
                            .padding(.horizontal, 16)

                        VStack(spacing: 8) {
                            HighContrastToggle()
                            AeroDataStatusRow(database: mapState.aeroData)
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 40)
                }
            }
        }
        .frame(maxWidth: layout.panelWidth ?? .infinity,
               maxHeight: layout.isSidePanel ? .infinity
                   : (isExpanded ? layout.expandedHeight(in: windowHeight) : nil),
               alignment: layout.isSidePanel ? .top : .bottom)
        .padding(.bottom, isOpen ? 0 : 20)
        // Background drawn as its own layer that ignores the bottom safe area.
        //
        // Two bugs lived in the previous version. `.background(_:in:)` sizes its
        // shape to the view's layout bounds, so it did not reliably fill the region
        // opened up by `.ignoresSafeArea` — leaving a strip of map visible beneath
        // the sheet on some SDKs. And clipping to a plain RoundedRectangle rounded
        // all four corners, so where that strip appeared the sheet read as a
        // floating card rather than something anchored to the bottom of the screen.
        // Only the top corners should be round.
        .background(
            AeroSurfaceFill(role: .panel, shape: surfaceShape)
                .ignoresSafeArea(edges: layout.isSidePanel ? [.bottom, .top] : .bottom)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: -5)
        // The panel does not drag; only the sheet does.
        .gesture(
            layout.isSidePanel ? nil : DragGesture(minimumDistance: 15)
                .onEnded { value in
                    if value.translation.height < -20 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isExpanded = true
                        }
                    } else if value.translation.height > 20 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isExpanded = false
                        }
                        hideKeyboard()
                    }
                }
        )
        .ignoresSafeArea(edges: layout.isSidePanel ? [] : .bottom)
        .onChange(of: mapState.searchText) { newValue in
            mapState.performLiveAirportSearch(query: newValue)
        }
        // Dropping a waypoint deliberately does NOT open the sheet. Placing points
        // by press-and-hold is a map task, and expanding over the map interrupts it.
        // The status banner reports what has been dropped; the pilot swipes up (or
        // taps "Plan") when they are ready to work on altitudes and tools.
    }
}

// MARK: - Route Totals

/// Distance / time / fuel for the whole route, computed from the vertical profile
/// so climb and descent legs are costed at their own speed and burn rather than
/// everything being flown at cruise.
struct RouteTotalsView: View {
    @ObservedObject var mapState: MapState

    private var profile: AltitudeProfile { mapState.altitudeProfile }

    var body: some View {
        HStack(spacing: 0) {
            totalBlock(title: "Distance",
                       value: "\(Int(profile.totalDistanceNM.rounded()))",
                       unit: "NM", icon: "ruler", tint: .cyan)
            divider
            totalBlock(title: "Time",
                       value: formattedTime(profile.totalTimeMinutes),
                       unit: "", icon: "clock", tint: .blue)
            divider
            totalBlock(title: "Fuel",
                       value: String(format: "%.1f", profile.totalFuelGallons),
                       unit: "gal", icon: "fuelpump", tint: .orange)
        }
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 30)
    }

    private func totalBlock(title: String, value: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Label(title, systemImage: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(tint.opacity(0.9))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(.white)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 9)).foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formattedTime(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
    }
}

// MARK: - Refine bar

/// What you do to a route once it exists. Generating, checking and comparing
/// alternatives all live behind Route Advisor — they are the same question asked
/// three ways, and splitting them across the screen made the toolbar noisier than
/// the job warranted.
struct RouteRefineBar: View {
    @ObservedObject var mapState: MapState

    var body: some View {
        HStack(spacing: 10) {
            action("Route Advisor", "wand.and.stars", .yellow) {
                mapState.assistantTab = "generate"
                mapState.showingAssistant = true
            }
            action("Check Route", "checkmark.shield.fill", .green) {
                mapState.assistantTab = "validate"
                mapState.showingAssistant = true
            }
            action("Profile", "chart.line.uptrend.xyaxis", .cyan) {
                mapState.showingProfileView = true
            }
        }
    }

    private func action(_ title: String, _ icon: String, _ tint: Color,
                        _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.subheadline).foregroundColor(tint)
                Text(title).font(.caption2).fontWeight(.bold).foregroundColor(.white)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(tint.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Aircraft

/// The airframe and the two numbers the pilot most often overrides on it. Placed
/// after the route because it is set once per flight, but kept visible because
/// every altitude and time above it depends on this choice.
struct AircraftCard: View {
    @ObservedObject var mapState: MapState

    private var aircraft: AircraftProfile { mapState.route.aircraft }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The name lives on the chip in the layer strip, which is on screen
            // whether this sheet is open or not. Repeating it here was noise; what
            // this card is for is the two numbers a pilot actually tunes per flight.
            HStack(spacing: 14) {
                stepper(title: "Cruise speed",
                        value: "\(Int(mapState.route.cruiseKTAS)) kt",
                        down: { mapState.route.cruiseKTAS = max(40, mapState.route.cruiseKTAS - 5) },
                        up: { mapState.route.cruiseKTAS = min(400, mapState.route.cruiseKTAS + 5) })

                Divider().frame(height: 32).background(Color.white.opacity(0.2))

                stepper(title: "Fuel aboard",
                        value: String(format: "%.0f gal", mapState.route.fuelOnBoardGal),
                        down: { mapState.route.fuelOnBoardGal = max(0, mapState.route.fuelOnBoardGal - 2) },
                        up: { mapState.route.fuelOnBoardGal = min(aircraft.usableFuelGal, mapState.route.fuelOnBoardGal + 2) })

                Spacer()
            }
        }
    }

    private func stepper(title: String, value: String,
                         down: @escaping () -> Void, up: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.white.opacity(0.6))
            HStack(spacing: 6) {
                Button(action: down) { Image(systemName: "minus.circle.fill").foregroundColor(.blue) }
                    .buttonStyle(PlainButtonStyle())
                Text(value)
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                    .frame(minWidth: 58)
                Button(action: up) { Image(systemName: "plus.circle.fill").foregroundColor(.blue) }
                    .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Secondary tools

/// Briefing and reference screens. Deliberately smaller and further down than the
/// refine bar — these are things a pilot reaches for, not the main flow.
struct SecondaryToolsView: View {
    @ObservedObject var mapState: MapState

    private var hasRoute: Bool { mapState.route.waypoints.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BRIEFING & REFERENCE")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(.white.opacity(0.45))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Route-only tools are omitted rather than dimmed until there is
                    // a route for them to work on.
                    if hasRoute {
                        ActionButton(title: "Procedure\nAdvisor", icon: "arrow.triangle.merge",
                                     color: .purple, enabled: true) {
                            mapState.showingProcedureAdvisor = true
                        }
                    }
                    ActionButton(title: "Airport\nDiagram", icon: "doc.richtext",
                                 color: .green, enabled: true) {
                        mapState.showingPlates = true
                    }
                    ActionButton(title: "Weight\n& Balance", icon: "scalemass",
                                 color: .yellow, enabled: true) {
                        mapState.showingFlightPlanner = true
                    }
                    ActionButton(title: "Checklist", icon: "checklist",
                                 color: .cyan, enabled: true) {
                        mapState.showingChecklist = true
                    }
                    ActionButton(title: "Weather\nBrief", icon: "cloud.sun.fill",
                                 color: .orange, enabled: true) {
                        mapState.showingWeatherPanel = true
                    }
                    ActionButton(title: "Notes", icon: "pencil.and.list.clipboard",
                                 color: .gray, enabled: true) {
                        mapState.showingNotes = true
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(enabled ? color : color.opacity(0.35))

                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(enabled ? .white : .white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 70, height: 62)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled)
    }
}

// MARK: - Mode Chip Button
struct ModeChipButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .medium)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isSelected ? Color.blue : Color.black.opacity(0.3))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.blue : Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Route Status Banner

/// The card under the search bar. It reflects what the route is actually doing:
/// planned routes offer Start and Save, a route already being flown shows progress
/// and the way out. Previously the Start/Save pair stayed on screen after Start,
/// which read as though the route had not begun.
struct ConfirmFlightPlanBanner: View {
    @ObservedObject var mapState: MapState
    @Binding var isExpanded: Bool

    private var originICAO: String { mapState.route.waypoints.first?.icao ?? "" }
    private var destICAO: String { mapState.route.waypoints.last?.icao ?? "" }
    private var totalDistNM: Int { Int(mapState.route.totalDistanceNM) }

    var body: some View {
        Group {
            if mapState.isNavigatingRoute {
                inFlightCard
            } else if mapState.route.waypoints.count < 2 {
                draftCard
            } else {
                plannedCard
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(accent.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.6), lineWidth: 1.5)
        )
        .padding(.horizontal, 14)
    }

    private var accent: Color {
        if mapState.isNavigatingRoute { return .cyan }
        return mapState.route.waypoints.count < 2 ? .blue : .green
    }

    private func expandSheet() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isExpanded = true }
    }

    // MARK: Draft — one point down, still being built on the map

    /// Shown from the first dropped waypoint. It reports progress without taking
    /// the map away, so press-and-hold can keep placing points.
    private var draftCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "hand.tap.fill")
                    .font(.subheadline)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 1) {
                    Text("BUILDING ROUTE — \(mapState.route.waypoints.count) POINT")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("Hold the map to add a destination")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { mapState.clearRoute() }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.9))
                        .padding(6)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Only while the sheet is closed. Shown when it is already open the
            // button had nothing left to do, which read as a dead control.
            if !isExpanded {
                Button(action: expandSheet) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.up").font(.caption2)
                        Text("Open route planner").font(.caption).fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: Planned

    private var plannedCard: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundColor(.green)
                    Text("ROUTE PLANNED")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.green)
                }

                Spacer()

                Text("\(originICAO) → \(destICAO) • \(totalDistNM) NM")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { mapState.clearRoute() }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.9))
                        .padding(6)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        mapState.startRouteNavigation()
                        isExpanded = false
                    }
                } label: {
                    pillLabel("Start Route", icon: "play.fill", background: .green, foreground: .black)
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    mapState.saveCurrentRoute()
                } label: {
                    pillLabel("Save Route", icon: "square.and.arrow.down.fill", background: .blue, foreground: .white)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Points at the planning surface without opening it unbidden.
            if !isExpanded {
                Button(action: expandSheet) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                        Text("Swipe up for altitudes, profile and tools")
                            .font(.caption2).fontWeight(.medium)
                        if let suggestion = mapState.cruiseSuggestion,
                           suggestion.altitudeFT != mapState.route.altitudeFT {
                            Text("· suggests \(suggestion.altitudeFT.formatted()) ft")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(.yellow)
                        }
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: In flight

    private var inFlightCard: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "location.north.line.fill")
                        .font(.headline)
                        .foregroundColor(.cyan)
                    Text("IN FLIGHT")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.cyan)
                }

                Spacer()

                Text("\(legProgressText) • \(remainingNM) NM to run")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            ProgressView(value: progressFraction)
                .tint(.cyan)

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        mapState.completeRoute()
                    }
                } label: {
                    pillLabel("Finish Flight", icon: "flag.checkered", background: .cyan, foreground: .black)
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        mapState.cancelRouteNavigation()
                    }
                } label: {
                    pillLabel("Cancel", icon: "xmark", background: Color.white.opacity(0.15), foreground: .white)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var legProgressText: String {
        let total = max(mapState.route.waypoints.count - 1, 1)
        let current = min(mapState.currentWaypointIndex + 1, total)
        return "Leg \(current) of \(total)"
    }

    private var progressFraction: Double {
        let total = max(Double(mapState.route.waypoints.count - 1), 1)
        return min(Double(mapState.currentWaypointIndex) / total, 1)
    }

    private var remainingNM: Int {
        let waypoints = mapState.route.waypoints
        guard waypoints.count >= 2 else { return 0 }
        let from = max(0, min(mapState.currentWaypointIndex, waypoints.count - 1))
        var sum: Double = 0
        for i in from..<(waypoints.count - 1) {
            sum += AltitudePlanner.distanceNM(waypoints[i].coordinate, waypoints[i + 1].coordinate)
        }
        return Int(sum.rounded())
    }

    private func pillLabel(_ title: String, icon: String, background: Color, foreground: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2)
            Text(title).font(.caption).fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(background)
        .foregroundColor(foreground)
        .clipShape(Capsule())
    }
}
