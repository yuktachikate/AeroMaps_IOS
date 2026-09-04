import UIKit

/// Bitmap builders for the annotation glyphs drawn on the map.
///
/// Everything here rasterises through `UIGraphicsImageRenderer` on purpose.
/// `UIImage.withTintColor(_:renderingMode:)`, `SymbolConfiguration(hierarchicalColor:)`
/// and `SymbolConfiguration(paletteColors:)` all defer the tint to *draw* time — the
/// backing `cgImage` stays pure black. `MKAnnotationView` hands `image.cgImage`
/// straight to its layer and never performs that draw-time pass, so a symbol coloured
/// any of those ways lands on the map as a solid black silhouette. Drawing the
/// template into a renderer bakes real coloured pixels, which survives the handoff.
enum MapSymbols {

    /// An SF Symbol with `color` baked into its pixels.
    static func symbol(_ name: String,
                       pointSize: CGFloat,
                       weight: UIImage.SymbolWeight = .regular,
                       color: UIColor,
                       traits: UITraitCollection? = nil) -> UIImage? {
        let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let template = UIImage(systemName: name, withConfiguration: cfg)?
            .withRenderingMode(.alwaysTemplate) else { return nil }

        let resolved = traits.map { color.resolvedColor(with: $0) } ?? color
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: template.size, format: format).image { _ in
            resolved.set()
            template.draw(in: CGRect(origin: .zero, size: template.size))
        }
    }

    /// Airport marker: a hangar silhouette in a rounded badge.
    ///
    /// An earlier version drew the sectional convention — a filled circle with the
    /// runway pattern struck through it. On screen that reads as a "no entry" sign,
    /// because a diagonal bar across a filled disc is exactly that symbol. A hangar
    /// is unambiguous at marker size and needs no chart-reading to interpret.
    ///
    /// Towered fields are a deeper orange than non-towered ones, so the two are
    /// separable without a second colour competing with the traffic and route
    /// layers.
    static func airportSymbol(towered: Bool,
                              runwayHeadings: [Double] = [],
                              diameter: CGFloat = 20) -> UIImage {
        // Orange throughout, a shade darker for towered fields so the two are still
        // distinguishable at a glance without changing hue.
        let tint: UIColor = towered ? UIColor(red: 0.90, green: 0.45, blue: 0.05, alpha: 1)
                                    : UIColor(red: 0.97, green: 0.65, blue: 0.22, alpha: 1)
        let size = CGSize(width: diameter, height: diameter)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext

            // Rounded badge with a white edge so it reads over terrain and water.
            let badge = CGRect(x: 1.5, y: 1.5, width: diameter - 3, height: diameter - 3)
            let badgePath = UIBezierPath(roundedRect: badge, cornerRadius: diameter * 0.28)
            c.setFillColor(UIColor.white.cgColor)
            c.addPath(UIBezierPath(roundedRect: badge.insetBy(dx: -1.5, dy: -1.5),
                                   cornerRadius: diameter * 0.34).cgPath)
            c.fillPath()
            c.setFillColor(tint.cgColor)
            c.addPath(badgePath.cgPath)
            c.fillPath()

            // Hangar: a quonset arch sitting on the ground line.
            let inset = diameter * 0.26
            let left = badge.minX + inset * 0.75
            let right = badge.maxX - inset * 0.75
            let ground = badge.maxY - inset * 0.72
            let eaves = badge.midY + diameter * 0.02

            let hangar = UIBezierPath()
            hangar.move(to: CGPoint(x: left, y: ground))
            hangar.addLine(to: CGPoint(x: left, y: eaves))
            hangar.addQuadCurve(to: CGPoint(x: right, y: eaves),
                                controlPoint: CGPoint(x: badge.midX, y: badge.minY + inset * 0.55))
            hangar.addLine(to: CGPoint(x: right, y: ground))
            hangar.close()

            c.setFillColor(UIColor.white.cgColor)
            c.addPath(hangar.cgPath)
            c.fillPath()

            // Door opening, punched back out in the badge colour.
            let doorWidth = (right - left) * 0.46
            let door = CGRect(x: badge.midX - doorWidth / 2,
                              y: ground - (ground - eaves) * 0.78,
                              width: doorWidth,
                              height: (ground - eaves) * 0.78)
            c.setFillColor(tint.cgColor)
            c.addPath(UIBezierPath(roundedRect: door, cornerRadius: doorWidth * 0.22).cgPath)
            c.fillPath()
        }
    }

    /// Kept for callers that only need a plain marker.
    static func airportRoundel(color: UIColor = .systemIndigo, diameter: CGFloat = 16) -> UIImage {
        airportSymbol(towered: true, diameter: diameter)
    }

    /// Numbered route waypoint: a filled diamond with its sequence number beside it.
    static func waypointDiamond(index: Int, isEndpoint: Bool, color: UIColor) -> UIImage {
        let size = CGSize(width: 22, height: 22)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let r: CGFloat = isEndpoint ? 8 : 6.5

            let path = CGMutablePath()
            path.move(to: CGPoint(x: mid.x, y: mid.y - r))
            path.addLine(to: CGPoint(x: mid.x + r, y: mid.y))
            path.addLine(to: CGPoint(x: mid.x, y: mid.y + r))
            path.addLine(to: CGPoint(x: mid.x - r, y: mid.y))
            path.closeSubpath()

            c.setFillColor(color.cgColor)
            c.addPath(path)
            c.fillPath()
            c.setStrokeColor(UIColor.white.cgColor)
            c.setLineWidth(2)
            c.addPath(path)
            c.strokePath()

            if !isEndpoint {
                let label = "\(index)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 8, weight: .heavy),
                    .foregroundColor: UIColor.white
                ]
                let textSize = label.size(withAttributes: attrs)
                label.draw(at: CGPoint(x: mid.x - textSize.width / 2, y: mid.y - textSize.height / 2), withAttributes: attrs)
            }
        }
    }
}
