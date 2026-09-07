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
    /// The one search model for the app. It lives here, at the top of the sheet,
    /// rather than inside the route builder — see UnifiedSearch.swift for why there
    /// used to be two of these and why the capable one being the hidden one was the
    /// problem.
    @StateObject private var search = WaypointSearchModel()
    /// The result the pilot tapped into, if any. Non-nil swaps the results list for
    /// the card, which is the "look at what you found before routing to it" beat.
    @State private var selection: WaypointSuggestion?
    /// The search field's text, deliberately local rather than on MapState.
    ///
    /// It lived on MapState and typing a single character therefore published to
    /// every view observing it — the whole sheet, the nearby-airports strip and its
    /// spatial query, and MapView's `updateUIView`, which touches MKMapView. That is
    /// the same trap the Save Route dialog documents a few files over: a text field
    /// bound to shared observable state re-runs the map on every keystroke, and
    /// typing "KSFO" stalls on the K.
    @State private var searchText = ""

    private var layout: PlanningLayout {
        PlanningLayout(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    private var isOpen: Bool { isExpanded }

    /// Swipe to open and close the sheet.
    ///
    /// Declared once and attached with `simultaneousGesture` to the surfaces a
    /// finger actually lands on, rather than relying on the plain `.gesture` on the
    /// sheet as a whole. That alone did not work: when the sheet is collapsed
    /// almost every pixel of it belongs to a child view that wins the gesture
    /// outright — the search field is a UITextField carrying its own pan
    /// recognisers, and the layer chips are a horizontal UIScrollView, which claims
    /// vertical pans as well as horizontal ones. A parent `.gesture` loses to both,
    /// so the only draggable area left was a few points of padding between them.
    ///
    /// `simultaneousGesture` runs alongside those recognisers instead of competing
    /// with them, and a tap never travels far enough to trigger it, so tapping into
    /// the search field still focuses it.
    private var sheetDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                if value.translation.height < -20 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isExpanded = true }
                } else if value.translation.height > 20 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isExpanded = false }
                    hideKeyboard()
                }
            }
    }
    
    /// Matches the search bar's radius, so the sheet and the first control inside
    /// it agree. Only the top corners round: the sheet is anchored to the bottom of
    /// the window, so rounding the bottom would make it read as a floating card.
    private static let cornerRadius: CGFloat = 16

    private var surfaceShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: Self.cornerRadius,
                               bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0,
                               topTrailingRadius: Self.cornerRadius,
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

    /// What the search field asks for, phrased for what it will do with the answer.
    /// Mid-route it is adding a stop, not starting over.
    private var searchPlaceholder: String {
        mapState.route.waypoints.isEmpty
            ? "Search airports, places, or coordinates"
            : "Add a stop — ident, place, or coordinates"
    }

    private var currentRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: mapState.camera.centerCoordinate,
                           span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2))
    }

    private func runSearch(_ text: String) {
        selection = nil
        // Only the debounced model is driven here. The global airport lookup used to
        // run on every keystroke too, and it sets `isSearchingLive` immediately —
        // a second full re-render per character on top of the one above. It now runs
        // from inside the model's debounce instead, via `onDebounced`.
        search.update(query: text,
                      airports: mapState.airports,
                      liveResults: mapState.liveSearchResults,
                      near: currentRegion)
    }

    /// Adds a result to the route and gets the search out of the way, because the
    /// next thing the pilot does is look at the route, not at more results.
    private func add(_ suggestion: WaypointSuggestion) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            mapState.appendWaypoint(suggestion.makeWaypoint())
        }
        selection = nil
        searchText = ""
        search.clear()
        hideKeyboard()
        // The route is only worth framing once there is a leg to frame.
        if mapState.route.waypoints.count >= 2 { mapState.zoomToRoute() }
        // A first waypoint means planning has started, so show the planning surface.
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isExpanded = true }
    }

    var body: some View {
        VStack(spacing: 10) {
            // The grabber carries the swipe. The search bar deliberately does NOT.
            //
            // It used to: the two were wrapped together so a swipe anywhere along the
            // top of the sheet would open it. That broke typing. Tapping the field
            // focuses it, which expands the sheet, which animates the field upward
            // under a finger that is still down — and that relative movement reads as
            // a downward drag. The gesture ended, called hideKeyboard(), and the
            // keyboard closed after a single character. "KSFO" got as far as "K".
            //
            // The grabber, the layer chips and the sheet's own background are still
            // draggable, which is enough for the swipe to feel natural without
            // putting a competing gesture on top of a text field.
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                    // Five points is a fine target to look at and a poor one to hit;
                    // the tappable area is enlarged without moving anything.
                    .contentShape(Rectangle().inset(by: -14))
            }
            .simultaneousGesture(sheetDrag)

            // 1. Search Bar (At top of bottom sheet, like Apple Maps)
            SearchBar(
                text: $searchText,
                isExpanded: $isExpanded,
                placeholder: searchPlaceholder,
                onSearch: {
                    // Enter takes the top hit. Typing an ident and pressing go is the
                    // fastest path there is, and it should not require aiming at a row.
                    if let first = search.suggestions.first { add(first) }
                }
            )
            .padding(.horizontal, 14)
            
            // Route status, from the first dropped point through to in-flight.
            if !mapState.route.waypoints.isEmpty {
                ConfirmFlightPlanBanner(mapState: mapState, isExpanded: $isExpanded)
            }
            
            // Results, or the card for whichever result was tapped. One list, and
            // it carries airports, places and coordinates rather than airports alone.
            if let selection {
                SearchResultCard(mapState: mapState,
                                 suggestion: selection,
                                 onAdd: { add(selection) },
                                 onDismiss: { self.selection = nil })
                    .padding(.horizontal, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !searchText.isEmpty {
                unifiedResults
            }

            // 2. Layer Control Pallets (Traffic, Radar, Airspace, FFM Risk)
            LayerControls(mapState: mapState)
                .padding(.horizontal, 14)
                .padding(.bottom, isOpen ? 0 : 24)
                .simultaneousGesture(sheetDrag)
            
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

                        LogbookRow(mapState: mapState)
                            .padding(.horizontal, 14)

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
               maxHeight: isExpanded ? layout.expandedHeight(in: windowHeight) : nil,
               alignment: .bottom)
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
                .ignoresSafeArea(edges: .bottom)
        )

        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: -5)
        // Catches swipes on the sheet's own background — the gaps between controls.
        // Deliberately the low-priority form: when the sheet is open its content
        // scrolls vertically, and a simultaneous gesture here would drive the sheet
        // and the scroll view at the same time.
        //
        // No `.contentShape(Rectangle())` here on purpose. It would make the sheet's
        // whole frame — transparent regions included — swallow touches that used to
        // fall through to the map behind it, which is a large area to make dead for
        // the sake of a gesture the grab area already handles.
        .gesture(sheetDrag)
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: searchText) { newValue in
            runSearch(newValue)
        }
        .onAppear {
            // Deferred to the model's debounce so it costs one lookup per pause
            // rather than one per character.
            search.onDebounced = { [weak mapState] query in
                mapState?.performLiveAirportSearch(query: query)
            }
        }
        // Dropping a waypoint deliberately does NOT open the sheet. Placing points
        // by press-and-hold is a map task, and expanding over the map interrupts it.
        // The status banner reports what has been dropped; the pilot swipes up (or
        // taps "Plan") when they are ready to work on altitudes and tools.
    }

    /// The single results list: airports from the bundled database, places from the
    /// map, and a coordinate if what was typed parses as one.
    @ViewBuilder
    private var unifiedResults: some View {
        VStack(spacing: 4) {
            if search.suggestions.isEmpty {
                HStack(spacing: 10) {
                    if search.isSearching {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        Text("Searching…")
                            .font(.subheadline).foregroundColor(.cyan)
                    } else {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        Text("Nothing matching '\(searchText)'")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 4) {
                        ForEach(search.suggestions) { suggestion in
                            SearchResultRow(
                                suggestion: suggestion,
                                onOpen: {
                                    withAnimation(.easeOut(duration: 0.2)) { selection = suggestion }
                                    hideKeyboard()
                                },
                                onAdd: { add(suggestion) }
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .frame(maxHeight: 240)
            }
        }
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
/// Previous flights, given a row of its own.
///
/// This was a chip inside the horizontally scrolling briefing strip, which meant
/// finding it required expanding the sheet and then scrolling sideways past six
/// other tools — so the flight log looked, reasonably, like it had never been
/// built. It states how many flights are recorded, which is also the answer to
/// "is this thing actually saving anything".
struct LogbookRow: View {
    @ObservedObject var mapState: MapState

    private var count: Int { mapState.flightLog.records.count }

    var body: some View {
        Button { mapState.activeTool = .logbook } label: {
            HStack(spacing: 10) {
                Image(systemName: "book.closed.fill")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Previous flights")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(count == 0
                         ? "No flights recorded yet"
                         : "\(count) flight\(count == 1 ? "" : "s") · \(String(format: "%.1f", mapState.flightLog.totalHours)) hours")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

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
                    // Airborne, the amendment tool is the one that matters, so it
                    // leads — a runway assignment is not something to go hunting for
                    // at the far end of a scrolling row with one hand on the yoke.
                    if mapState.isNavigatingRoute {
                        ActionButton(title: "Amend\nRoute", icon: "arrow.triangle.branch",
                                     color: .orange, enabled: true) {
                            mapState.activeTool = .amend
                        }
                    }
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
            if mapState.isNavigatingRoute && mapState.routeCompleted {
                flightCompleteCard
            } else if mapState.isNavigatingRoute {
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

            // What the profile wants the aircraft doing vertically. The plan always
            // knew this; in the air it was never said, so the pilot had to read it
            // off the waypoint list themselves.
            if let guidance = mapState.altitudeGuidance {
                HStack(spacing: 8) {
                    Image(systemName: guidanceIcon(guidance))
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(guidanceTint(guidance))
                    Text(guidance.label)
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(guidanceTint(guidance))
                    if let current = guidance.currentFT, guidance.action != .maintain {
                        Text("(now \(current.formatted()) ft)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                    if let tod = guidance.toTopOfDescentNM {
                        Text("TOD in \(Int(tod.rounded())) NM")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(guidanceTint(guidance).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }

            ProgressView(value: progressFraction)
                .tint(.cyan)

            // Checklist and notes belong in reach while flying, not buried in a
            // horizontally scrolling row inside the expanded sheet.
            HStack(spacing: 8) {
                Button { mapState.showingChecklist = true } label: {
                    inFlightChip("Checklist", icon: "checklist",
                                 badge: mapState.checkedChecklistItems.isEmpty
                                     ? nil : "\(mapState.checkedChecklistItems.count)")
                }
                .buttonStyle(PlainButtonStyle())

                Button { mapState.showingNotes = true } label: {
                    inFlightChip("Notes", icon: "pencil.and.list.clipboard",
                                 badge: mapState.flightNotes.isEmpty ? nil : "•")
                }
                .buttonStyle(PlainButtonStyle())

                Button { mapState.activeTool = .amend } label: {
                    inFlightChip("Amend", icon: "arrow.triangle.branch", badge: nil)
                }
                .buttonStyle(PlainButtonStyle())
            }

            HStack(spacing: 10) {
                // One obvious action, named for where the aircraft actually is.
                // "Finish Flight" and "Cancel" were two ways to end the same flight
                // differing only in a completion flag, and neither was the thing a
                // pilot wants partway down a route with a stop in it.
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        if mapState.isApproachingStop { mapState.arriveAtStop() }
                        else { mapState.completeRoute() }
                    }
                } label: {
                    pillLabel(mapState.isApproachingStop
                                ? "Arrived at \(mapState.nextWaypoint?.ident ?? "stop")"
                                : "Finish Flight",
                              icon: mapState.isApproachingStop ? "pause.circle.fill" : "flag.checkered",
                              background: .cyan, foreground: .black)
                }
                .buttonStyle(PlainButtonStyle())

                // Ending early is rare and not the same as arriving, so it sits
                // behind a menu rather than beside the primary action.
                Menu {
                    Button(role: .destructive) {
                        withAnimation { mapState.cancelRouteNavigation() }
                    } label: { Label("End flight early", systemImage: "xmark.circle") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 34)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func inFlightChip(_ title: String, icon: String, badge: String?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(title).font(.system(size: 11, weight: .semibold))
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.cyan.opacity(0.35))
                    .clipShape(Capsule())
            }
        }
        .foregroundColor(.white.opacity(0.9))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func guidanceIcon(_ g: MapState.AltitudeGuidance) -> String {
        switch g.action {
        case .climb:    return "arrow.up.right.circle.fill"
        case .descend:  return "arrow.down.right.circle.fill"
        case .maintain: return "equal.circle.fill"
        }
    }

    private func guidanceTint(_ g: MapState.AltitudeGuidance) -> Color {
        switch g.action {
        case .climb:    return .green
        case .descend:  return .orange
        case .maintain: return .cyan
        }
    }

    /// Shown once the final waypoint is reached. The flight is over, so the card
    /// stops offering flight controls and offers the record instead.
    private var flightCompleteCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.headline).foregroundColor(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("FLIGHT COMPLETE")
                        .font(.caption2).fontWeight(.bold).foregroundColor(.green)
                    Text(mapState.route.displayName)
                        .font(.caption).foregroundColor(.white).lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    mapState.activeTool = .logbook
                } label: {
                    pillLabel("View summary", icon: "doc.text.magnifyingglass",
                              background: .green, foreground: .black)
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        mapState.cancelRouteNavigation()
                    }
                } label: {
                    pillLabel("Done", icon: "checkmark",
                              background: Color.white.opacity(0.15), foreground: .white)
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
