import SwiftUI
import MapKit

/// Drives an embedded preview map from SwiftUI — zoom buttons and "fit the route"
/// need a handle on the underlying MKMapView, which a plain UIViewRepresentable
/// does not expose.
final class RoutePreviewController: ObservableObject {
    fileprivate weak var mapView: MKMapView?
    fileprivate var waypoints: [Waypoint] = []

    func zoomIn() { scale(by: 0.45) }
    func zoomOut() { scale(by: 2.2) }

    private func scale(by factor: Double) {
        guard let mapView else { return }
        var region = mapView.region
        // Clamp so a pinch cannot invert or overflow the projection.
        region.span = MKCoordinateSpan(
            latitudeDelta: min(max(region.span.latitudeDelta * factor, 0.002), 140),
            longitudeDelta: min(max(region.span.longitudeDelta * factor, 0.002), 140))
        mapView.setRegion(region, animated: true)
    }

    /// Frames the whole route again after the pilot has zoomed around.
    func fitRoute(animated: Bool = true) {
        guard let mapView, waypoints.count >= 2 else { return }
        let coords = waypoints.map(\.coordinate)
        let line = MKPolyline(coordinates: coords, count: coords.count)
        mapView.setVisibleMapRect(line.boundingMapRect,
                                  edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                                  animated: animated)
    }
}

/// A map showing a whole route at a glance.
///
/// Embedded in a card it zooms but does not pan: a scrollable map inside a
/// scrolling sheet swallows every vertical drag, so panning is left to the
/// full-screen presentation, which has no such conflict.
struct RoutePreviewMap: UIViewRepresentable {
    let waypoints: [Waypoint]
    var controller: RoutePreviewController? = nil
    /// Full-screen presentation: pan, rotate and pitch as well as zoom.
    var allowsPanning: Bool = false

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isZoomEnabled = true
        map.isScrollEnabled = allowsPanning
        map.isRotateEnabled = allowsPanning
        map.isPitchEnabled = allowsPanning
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = allowsPanning
        map.showsScale = allowsPanning
        map.mapType = .mutedStandard
        controller?.mapView = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        controller?.mapView = map
        controller?.waypoints = waypoints

        let signature = waypoints.map { "\($0.id)" }.joined()
        let isNewRoute = context.coordinator.signature != signature
        context.coordinator.signature = signature

        guard isNewRoute else { return }   // don't yank the camera back on every redraw

        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        guard waypoints.count >= 2 else { return }

        let coords = waypoints.map(\.coordinate)
        let line = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(line)

        for (index, wp) in waypoints.enumerated() {
            let annotation = RouteWaypointAnnotation()
            annotation.coordinate = wp.coordinate
            annotation.title = wp.ident
            annotation.subtitle = wp.reason ?? wp.kind.label
            annotation.index = index + 1
            annotation.isDeparture = index == 0
            annotation.isDestination = index == waypoints.count - 1
            map.addAnnotation(annotation)
        }

        // Inset generously so end markers are not clipped by the frame.
        map.setVisibleMapRect(line.boundingMapRect,
                              edgePadding: UIEdgeInsets(top: 34, left: 34, bottom: 34, right: 34),
                              animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator(showsCallouts: allowsPanning) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var signature = ""
        let showsCallouts: Bool

        init(showsCallouts: Bool) { self.showsCallouts = showsCallouts }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemCyan
            renderer.lineWidth = 3
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let wp = annotation as? RouteWaypointAnnotation else { return nil }
            let identifier = "PreviewWaypoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: wp, reuseIdentifier: identifier)
            view.annotation = wp
            view.canShowCallout = showsCallouts
            view.displayPriority = .required
            // Same rasterised-tint rule as the main map; see MapSymbols.
            if wp.isDeparture {
                view.image = MapSymbols.symbol("airplane.departure", pointSize: 13, weight: .bold, color: .systemGreen)
            } else if wp.isDestination {
                view.image = MapSymbols.symbol("airplane.arrival", pointSize: 13, weight: .bold, color: .systemRed)
            } else {
                view.image = MapSymbols.waypointDiamond(index: wp.index, isEndpoint: false, color: .systemCyan)
            }
            return view
        }
    }
}

// MARK: - Card

/// The preview as it appears inside a card: the map, zoom and fit controls, and a
/// way to open it full screen for a proper look.
struct RoutePreviewCard: View {
    let waypoints: [Waypoint]
    var height: CGFloat = 190

    @StateObject private var controller = RoutePreviewController()
    @State private var showingFullScreen = false

    var body: some View {
        RoutePreviewMap(waypoints: waypoints, controller: controller)
            .frame(height: height)
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    mapButton("plus") { controller.zoomIn() }
                    mapButton("minus") { controller.zoomOut() }
                    mapButton("arrow.up.left.and.arrow.down.right") { controller.fitRoute() }
                    mapButton("arrow.up.left.and.arrow.down.right.circle") { showingFullScreen = true }
                }
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .fullScreenCover(isPresented: $showingFullScreen) {
                RouteMapFullScreen(waypoints: waypoints)
            }
    }

    private func mapButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
                .frame(width: 28, height: 28)
                .background(.regularMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

/// The route on a full, freely interactive map — pan, zoom, rotate — for judging a
/// proposal properly before accepting it.
struct RouteMapFullScreen: View {
    let waypoints: [Waypoint]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = RoutePreviewController()

    var body: some View {
        ZStack(alignment: .top) {
            RoutePreviewMap(waypoints: waypoints, controller: controller, allowsPanning: true)
                .ignoresSafeArea()

            HStack {
                Button { dismiss() } label: {
                    Label("Done", systemImage: "chevron.down")
                        .font(.subheadline).fontWeight(.semibold)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(waypoints.first?.ident ?? "") → \(waypoints.last?.ident ?? "") · \(Int(AltitudePlanner.totalDistanceNM(waypoints).rounded())) NM")
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(Capsule())

                Spacer()

                Button { controller.fitRoute() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}
