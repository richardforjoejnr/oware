import LudoEngine
import SwiftUI

/// A colour to choose, after the owner's mockups: the pawn on its colour in a carved frame, brass
/// glow and a tick when chosen, and whatever goes under it (a name field, "Tap to add").
struct ColourTile<Footer: View>: View {
    let color: PlayerColor
    let chosen: Bool
    /// A pill under the tile ("You").
    var badge: String?
    let action: () -> Void
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Palette.color(color).opacity(0.85), Palette.color(color)],
                                                 center: .init(x: 0.4, y: 0.35), startRadius: 2, endRadius: 44))
                            .overlay(Circle().stroke(Palette.brass, lineWidth: 2.5))
                        Image(Art.pawn(color)).resizable().scaledToFit().padding(12)
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
                    }
                    .frame(width: 78, height: 78)
                    Text(color.name)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .engraved()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(color.name)
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .accessibilityIdentifier("colour-\(color.name.lowercased())")
            footer
        }
        .padding(8)
        .background(CarvedBlock(kind: .recessed, corner: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.brassLight, lineWidth: chosen ? 3 : 0))
        .shadow(color: chosen ? Palette.brassLight.opacity(0.7) : .clear, radius: 8)
        .overlay(alignment: .topTrailing) {
            if chosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Palette.night, Palette.brassLight)
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            if let badge, chosen {
                Label(badge, systemImage: "checkmark.circle.fill")
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(Palette.night)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Palette.brassLight))
                    .offset(y: 12)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Who plays which colour, as a row of pawns with names (under the tiles).
struct SeatSummary: View {
    let title: String
    let players: [(PlayerColor, String)]

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .foregroundStyle(Palette.ivory)
                .fixedSize()
            Rectangle().fill(Palette.brass.opacity(0.6)).frame(width: 1, height: 34)
            HStack(spacing: 8) {
                ForEach(players, id: \.0) { color, name in
                    VStack(spacing: 2) {
                        Image(Art.pawn(color)).resizable().scaledToFit().frame(height: 24)
                        Text(name).font(.system(.caption, design: .serif)).foregroundStyle(Palette.ivory)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(CarvedBlock(kind: .recessed, corner: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) " + players.map { $0.1 == $0.0.name ? $0.1 : "\($0.1), \($0.0.name)" }.joined(separator: "; "))
    }
}

/// "Random colour(s)": a small carved button with a die.
struct RandomColourButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(Art.die(5)).resizable().scaledToFit().frame(width: 28, height: 28)
                Text(title).font(.system(.body, design: .serif).weight(.semibold)).engraved()
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 46)
            .background(CarvedBlock(kind: .recessed, corner: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
