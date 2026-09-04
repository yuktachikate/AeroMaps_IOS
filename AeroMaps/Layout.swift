import SwiftUI

/// How the planning surface sits against the map.
///
/// This exists because the app previously decided its layout from
/// `verticalSizeClass == .compact`, read as "is landscape". That is true on an
/// iPhone and false on every iPad — an iPad reports a *regular* vertical size
/// class in both orientations — so a 13-inch iPad was laid out as though it were a
/// portrait phone, with a search field two feet wide.
///
/// Size classes describe available space, not orientation. The distinction that
/// actually matters here is whether there is room to show the map and the route at
/// the same time.
enum PlanningLayout {
    /// iPhone portrait: a sheet across the bottom, dragged up over the map.
    case bottomSheet
    /// iPhone landscape: the same sheet, but short and narrow so it does not bury
    /// the map in the little vertical space there is.
    case compactSheet
    /// iPad and other regular-width windows: a fixed side panel beside the map, so
    /// the route and the terrain it crosses are visible together. This is how a
    /// kneeboard-mounted iPad is actually flown.
    case sidePanel

    init(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) {
        if horizontal == .regular {
            self = .sidePanel
        } else if vertical == .compact {
            self = .compactSheet
        } else {
            self = .bottomSheet
        }
    }

    var isSidePanel: Bool { self == .sidePanel }

    /// Width of the planning surface. The side panel is fixed so the map keeps the
    /// rest; a sheet spans its window, capped in landscape.
    var panelWidth: CGFloat? {
        switch self {
        case .sidePanel:    return 400
        case .compactSheet: return 460
        case .bottomSheet:  return nil
        }
    }

    /// How much of the window the expanded surface may take. Not applicable to the
    /// side panel, which is always full height.
    func expandedHeight(in windowHeight: CGFloat) -> CGFloat? {
        switch self {
        case .sidePanel:    return nil
        case .compactSheet: return min(windowHeight * 0.92, 260)
        case .bottomSheet:  return windowHeight * 0.80
        }
    }

    /// Clearance for controls floating over the map, so they sit above the
    /// collapsed surface rather than behind it.
    var mapControlBottomInset: CGFloat {
        switch self {
        case .sidePanel:    return 32
        case .compactSheet: return 60
        case .bottomSheet:  return 170
        }
    }
}

private struct PlanningLayoutKey: EnvironmentKey {
    static let defaultValue = PlanningLayout.bottomSheet
}

extension EnvironmentValues {
    /// Read by every view that needs to lay out against the map, so the decision is
    /// made once rather than re-derived from size classes in six places.
    var planningLayout: PlanningLayout {
        get { self[PlanningLayoutKey.self] }
        set { self[PlanningLayoutKey.self] = newValue }
    }
}
