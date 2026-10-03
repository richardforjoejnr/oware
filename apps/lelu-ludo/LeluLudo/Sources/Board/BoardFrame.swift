import SwiftUI

/// The wooden box round the board, after the owner's art: dark grained rails, brass corner caps,
/// and the carved LELU LUDO plaque on its front.
struct BoardFrame<Content: View>: View {
    var plaque = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let rail = side * 0.045
                ZStack {
                    Image(Art.woodGrain).resizable(resizingMode: .tile)
                        .overlay(Color.black.opacity(0.15))
                    content()
                        .frame(width: side - 2 * rail, height: side - 2 * rail)
                        // The rails stand above the board: a soft shadow on the inside edge.
                        .overlay(Rectangle().stroke(.black.opacity(0.45), lineWidth: 2).blur(radius: 2))
                    ForEach(0..<4, id: \.self) { i in
                        BrassCap(size: rail * 1.6)
                            .rotationEffect(.degrees(Double(i) * 90))
                            .position(x: i == 0 || i == 3 ? rail * 0.8 : side - rail * 0.8,
                                      y: i < 2 ? rail * 0.8 : side - rail * 0.8)
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
        .shadow(color: .black.opacity(0.45), radius: 8, y: 5)
    }
}

/// A brass corner cap with a rivet (top-left orientation; rotated for the other corners).
struct BrassCap: View {
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: size * 0.25, bottomLeadingRadius: size * 0.1,
                                   bottomTrailingRadius: size * 0.45, topTrailingRadius: size * 0.1)
                .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.78, blue: 0.42), Palette.brass,
                                              Color(red: 0.45, green: 0.32, blue: 0.10)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: size * 0.25, bottomLeadingRadius: size * 0.1,
                                                bottomTrailingRadius: size * 0.45, topTrailingRadius: size * 0.1)
                    .stroke(.black.opacity(0.35), lineWidth: 1))
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.9, blue: 0.6), Palette.brass, Color(red: 0.35, green: 0.25, blue: 0.08)],
                                     center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.16))
                .frame(width: size * 0.3, height: size * 0.3)
                .offset(x: size * 0.25, y: size * 0.25)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
