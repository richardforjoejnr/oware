import SwiftUI

/// The sand cloth table every screen sits on, after the owner's art, darker towards the edges.
struct Table: View {
    var body: some View {
        ZStack {
            Image(Art.linen).resizable(resizingMode: .tile)
            RadialGradient(colors: [.clear, Color(red: 0.25, green: 0.14, blue: 0.06).opacity(0.45)],
                           center: .center, startRadius: 160, endRadius: 640)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A carved mahogany panel edged in brass: the status plaque, the tray, the Continue button.
struct WoodPanel: ViewModifier {
    var corner: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner)
                    .fill(ImagePaint(image: Image(Art.darkWoodAcross), scale: 0.5))
                    .overlay(RoundedRectangle(cornerRadius: corner).fill(
                        LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: corner).stroke(Palette.brass, lineWidth: 2))
                    .overlay(RoundedRectangle(cornerRadius: corner - 4).stroke(.black.opacity(0.35), lineWidth: 1).padding(4))
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 4)
            }
    }
}

extension View {
    func woodPanel(corner: CGFloat = 16) -> some View { modifier(WoodPanel(corner: corner)) }
}

/// A round wooden button with a brass rim (the back button).
struct WoodCircleButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ivory)
                .frame(width: 48, height: 48)
                .background(Circle().fill(ImagePaint(image: Image(Art.darkWood), scale: 0.4)))
                .overlay(Circle().stroke(Palette.brass, lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
