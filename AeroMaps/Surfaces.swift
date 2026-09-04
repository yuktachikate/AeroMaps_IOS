import SwiftUI

/// What a translucent surface is for, which decides how translucent it may be.
///
/// The distinction matters more in a cockpit than in most apps. Liquid Glass is
/// designed to let the content behind show through, and behind these surfaces is a
/// busy sectional — magenta and blue airspace, yellow traffic, cyan course lines.
/// That is fine behind a floating button and bad behind an altitude a pilot is
/// about to fly, especially in direct sun through polarised sunglasses.
enum SurfaceRole {
    /// Chrome floating over the map: a button, a badge, a chip. Nothing here is a
    /// number to act on, so translucency costs little and looks right.
    case floating
    /// A panel carrying figures the pilot reads and acts on. Legibility wins over
    /// fashion; these stay substantially more opaque.
    case panel
}

/// Applies the right background for a surface, given its role and the reader's
/// accessibility settings.
///
/// One modifier rather than scattered `.ultraThinMaterial` calls, so the legibility
/// policy lives in a single place and Reduce Transparency is honoured everywhere at
/// once instead of nowhere, which is where it stood before.
struct AeroSurface<S: InsettableShape>: ViewModifier {
    let role: SurfaceRole
    let shape: S
    var tint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(HighContrast.key) private var highContrast = false

    /// True when translucency should be abandoned altogether: either the system
    /// accessibility setting, or the pilot's own sunlight mode.
    private var wantsOpaque: Bool { reduceTransparency || highContrast }

    func body(content: Content) -> some View {
        if wantsOpaque {
            content
                .background(opaqueFill, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.35), lineWidth: 1))
        } else if role == .floating, #available(iOS 26.0, *) {
            // Liquid Glass, where it belongs: floating chrome.
            content
                .glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: shape)
        } else {
            content
                .background(role == .panel ? panelMaterial : .ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    /// Panels get the densest material available, not the thinnest. A route list
    /// over bright Class B was already washing out before any of this.
    private var panelMaterial: Material { .thickMaterial }

    private var opaqueFill: Color {
        tint ?? Color(white: 0.10)
    }
}

extension View {
    /// Standard app surface. Prefer this over a bare `.background(.ultraThinMaterial)`.
    func aeroSurface<S: InsettableShape>(_ role: SurfaceRole,
                                         in shape: S,
                                         tint: Color? = nil) -> some View {
        modifier(AeroSurface(role: role, shape: shape, tint: tint))
    }

    func aeroSurface(_ role: SurfaceRole, cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        modifier(AeroSurface(role: role,
                             shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                             tint: tint))
    }
}

/// The pilot-facing sunlight mode.
///
/// Worth more to this audience than any amount of translucency: flattens every
/// surface to a solid panel for reading a screen in a bright cockpit.
enum HighContrast {
    static let key = "AeroMaps_HighContrast"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Toggle for the sunlight mode, shown alongside the other display settings.
struct HighContrastToggle: View {
    @AppStorage(HighContrast.key) private var highContrast = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { highContrast.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: highContrast ? "sun.max.fill" : "sun.max")
                    .font(.system(size: 10))
                Text(highContrast ? "Sunlight mode on" : "Sunlight mode")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                if reduceTransparency && !highContrast {
                    Text("on via Reduce Transparency")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .foregroundColor(highContrast ? .yellow : .white.opacity(0.55))
        }
        .buttonStyle(PlainButtonStyle())
    }
}
