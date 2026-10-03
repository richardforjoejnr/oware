import SwiftUI

/// The wooden box round the board, after the owner's art: mitred mahogany rails with the grain
/// running along each, lit from above, brass corner caps, and the carved LELU LUDO plaque on its front.
struct BoardFrame<Content: View>: View {
    var plaque = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let rail = side * 0.05
                ZStack {
                    Rails(rail: rail)
                    content()
                        .frame(width: side - 2 * rail, height: side - 2 * rail)
                        // The rails stand above the board: shade on its edge.
                        .overlay(Rectangle().strokeBorder(.black.opacity(0.35), lineWidth: 3).blur(radius: 2.5))
                        .clipped()
                    ForEach(0..<4, id: \.self) { i in
                        BrassCap(size: rail * 1.7)
                            .rotationEffect(.degrees(Double(i) * 90))
                            .position(x: i == 0 || i == 3 ? rail * 0.85 : side - rail * 0.85,
                                      y: i < 2 ? rail * 0.85 : side - rail * 0.85)
                    }
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            if plaque {
                Image(Art.boardPlaque).resizable().scaledToFit()
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
    }
}

/// Four rails meeting at mitred corners: top and bottom with the grain across, the sides with it down.
private struct Rails: View {
    let rail: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let across = GraphicsContext.Shading.tiledImage(Image(Art.darkWoodAcross), scale: 0.5)
            let down = GraphicsContext.Shading.tiledImage(Image(Art.darkWood), scale: 0.5)
            func quad(_ pts: [CGPoint]) -> Path { var p = Path(); p.addLines(pts); p.closeSubpath(); return p }
            let top = quad([.zero, CGPoint(x: w, y: 0), CGPoint(x: w - rail, y: rail), CGPoint(x: rail, y: rail)])
            let bottom = quad([CGPoint(x: 0, y: h), CGPoint(x: w, y: h), CGPoint(x: w - rail, y: h - rail), CGPoint(x: rail, y: h - rail)])
            let left = quad([.zero, CGPoint(x: rail, y: rail), CGPoint(x: rail, y: h - rail), CGPoint(x: 0, y: h)])
            let right = quad([CGPoint(x: w, y: 0), CGPoint(x: w - rail, y: rail), CGPoint(x: w - rail, y: h - rail), CGPoint(x: w, y: h)])
            ctx.fill(top, with: across)
            ctx.fill(bottom, with: across)
            ctx.fill(left, with: down)
            ctx.fill(right, with: down)
            // Light from above: the top rail brightest, the bottom darkest; the sides in between.
            ctx.fill(top, with: .color(.white.opacity(0.10)))
            ctx.fill(bottom, with: .color(.black.opacity(0.30)))
            ctx.fill(left, with: .color(.black.opacity(0.08)))
            ctx.fill(right, with: .color(.black.opacity(0.16)))
            // Mitre joints and the rounded outer edge.
            for p in [top, bottom, left, right] { ctx.stroke(p, with: .color(.black.opacity(0.35)), lineWidth: 0.8) }
            ctx.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)), with: .color(.white.opacity(0.18)), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

/// A brass corner cap with a rivet (top-left orientation; rotated for the other corners).
struct BrassCap: View {
    let size: CGFloat

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: size * 0.25, bottomLeadingRadius: size * 0.1,
                                           bottomTrailingRadius: size * 0.45, topTrailingRadius: size * 0.1)
        ZStack(alignment: .topLeading) {
            shape
                .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.82, blue: 0.48), Palette.brass,
                                              Color(red: 0.45, green: 0.32, blue: 0.10)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(shape.stroke(.black.opacity(0.35), lineWidth: 1))
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.92, blue: 0.65), Palette.brass, Color(red: 0.35, green: 0.25, blue: 0.08)],
                                     center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.16))
                .frame(width: size * 0.3, height: size * 0.3)
                .offset(x: size * 0.25, y: size * 0.25)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        .accessibilityHidden(true)
    }
}
