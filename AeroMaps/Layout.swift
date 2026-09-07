import SwiftUI

/// How the planning surface is sized against the map.
///
/// This exists because the app previously decided its layout from
/// `verticalSizeClass == .compact`, read as "is landscape". That is true on an
/// iPhone and false on every iPad — an iPad reports a *regular* vertical size
/// class in both orientations — so a 13-inch iPad was laid out as though it were a
/// portrait phone, with a search field two feet wide.
///
/// Size classes describe available space, not orientation. Every case here is the
/// same bottom sheet with the same behaviour; only its width and height change.
/// Keeping one layout across devices is deliberate: a pilot who plans on an iPad
/// and flies with an iPhone should not meet two different apps.
enum PlanningLayout {
    /// iPhone portrait: a sheet across the bottom, dragged up over the map.
    case bottomSheet
    /// iPhone landscape: the same sheet, but short and narrow so it does not bury
    /// the map in the little vertical space there is.
    case compactSheet
    /// iPad: the same sheet again, centred and capped rather than stretched across
    /// the full width. One layout and one mental model across devices — a pilot
    /// moving between an iPhone and an iPad should not have to relearn the app.
    case wideSheet

    init(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) {
        // Vertical is tested first, and the order is the whole point. A large
        // iPhone — Plus and Max models — reports a *regular* horizontal size class
        // in landscape, exactly like an iPad. Asking about width first therefore
        // handed those phones the iPad layout whenever they were turned sideways:
        // a 680pt panel over 72% of an already short screen. Short height is the
        // stronger constraint, so it decides first, and only something with room in
        // both directions gets the wide sheet.
        if vertical == .compact {
            self = .compactSheet
        } else if horizontal == .regular {
            self = .wideSheet
        } else {
            self = .bottomSheet
        }
    }

    /// Width of the planning surface. Capped on larger screens: a search field
    /// spanning a 13-inch iPad is unusable, and the map is better off with the room.
    var panelWidth: CGFloat? {
        switch self {
        case .wideSheet:    return 680
        case .compactSheet: return 460
        case .bottomSheet:  return nil
        }
    }

    /// How much of the window the expanded surface may take.
    func expandedHeight(in windowHeight: CGFloat) -> CGFloat? {
        switch self {
        case .wideSheet:    return windowHeight * 0.72
        case .compactSheet: return min(windowHeight * 0.92, 260)
        case .bottomSheet:  return windowHeight * 0.80
        }
    }

    /// Clearance for controls floating over the map, so they sit above the
    /// collapsed surface rather than behind it.
    var mapControlBottomInset: CGFloat {
        switch self {
        case .wideSheet:    return 190
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
