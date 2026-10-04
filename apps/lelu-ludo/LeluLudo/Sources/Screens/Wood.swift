import SwiftUI

/// The sand cloth table every screen sits on, after the owner's art: linen, darker towards the edges,
/// with bands of pattern stamped into the cloth (chevrons up the sides, diamonds along the foot).
struct Table: View {
    var body: some View {
        ZStack {
            Image(Art.linen).resizable(resizingMode: .tile)
            ClothPattern()
            RadialGradient(colors: [.clear, Color(red: 0.25, green: 0.14, blue: 0.06).opacity(0.4)],
                           center: .center, startRadius: 160, endRadius: 640)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Patterns stamped into the cloth in a faded brown dye.
struct ClothPattern: View {
    var body: some View {
        Canvas { ctx, size in
            let ink = GraphicsContext.Shading.color(Color(red: 0.42, green: 0.27, blue: 0.15).opacity(0.28))
            // Chevrons up both sides.
            let band: CGFloat = 26
            for x in [band / 2, size.width - band / 2] {
                var y: CGFloat = 0
                while y < size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: x - band / 2 + 3, y: y))
                    p.addLine(to: CGPoint(x: x, y: y + 10))
                    p.addLine(to: CGPoint(x: x + band / 2 - 3, y: y))
                    ctx.stroke(p, with: ink, lineWidth: 3)
                    y += 16
                }
            }
            // Two rows of nested diamonds along the foot.
            let d: CGFloat = 34
            for row in 0..<2 {
                let cy = size.height - d * (CGFloat(row) + 0.5) - 6
                var x = d / 2 + (row == 1 ? d / 2 : 0)
                while x < size.width {
                    for inset in [0.0, 7.0] {
                        let r = d / 2 - inset
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: cy - r))
                        p.addLine(to: CGPoint(x: x + r, y: cy))
                        p.addLine(to: CGPoint(x: x, y: cy + r))
                        p.addLine(to: CGPoint(x: x - r, y: cy))
                        p.closeSubpath()
                        ctx.stroke(p, with: ink, lineWidth: 2.5)
                    }
                    x += d
                }
            }
            // A zigzag along the top.
            var z = Path()
            z.move(to: CGPoint(x: 0, y: 8))
            var zx: CGFloat = 0
            var up = true
            while zx < size.width {
                zx += 9
                z.addLine(to: CGPoint(x: zx, y: up ? 2 : 14))
                up.toggle()
            }
            ctx.stroke(z, with: ink, lineWidth: 2.5)
        }
        .allowsHitTesting(false)
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

/// The knot carved on the board box (the four-loop motif), drawn as a brass glyph.
struct KnotGlyph: View {
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: "command")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Palette.brassLight)
            .accessibilityHidden(true)
    }
}

/// A brass stud, as on the corners of the board box.
struct BrassStud: View {
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Palette.brassLight, Palette.brass, Palette.brassDark],
                                 center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A square brass plate with a stud, as on the corners of the board box and the menu's panels.
struct BrassPlate: View {
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.18)
            .fill(LinearGradient(colors: [Palette.brassLight, Palette.brass, Palette.brassDark], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(.black.opacity(0.45), lineWidth: 0.75))
            .overlay(BrassStud(size: size * 0.42))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1.5)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The knot in a small carved box, either side of a panel's title.
struct KnotBox: View {
    var body: some View {
        KnotGlyph(size: 17)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.3)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.brass.opacity(0.55), lineWidth: 1))
    }
}

/// Chevrons carved into the end of a panel's title strip.
struct CarvedChevrons: View {
    var body: some View {
        Canvas { ctx, size in
            for i in 0..<3 {
                let x = CGFloat(i) * size.width / 3 + 2
                var p = Path()
                p.move(to: CGPoint(x: x + size.width / 3 - 3, y: size.height * 0.15))
                p.addLine(to: CGPoint(x: x, y: size.height / 2))
                p.addLine(to: CGPoint(x: x + size.width / 3 - 3, y: size.height * 0.85))
                ctx.stroke(p, with: .color(.black.opacity(0.4)), lineWidth: 2.5)
                ctx.stroke(p.offsetBy(dx: 0, dy: 1), with: .color(Palette.brass.opacity(0.25)), lineWidth: 1)
            }
        }
        .frame(width: 22, height: 30)
        .accessibilityHidden(true)
    }
}

/// A carved panel, after the owner's mockups: a lighter mahogany frame with brass corner plates, a
/// title strip (chevrons, knot boxes, the title in brass), and the content on a darker inset.
struct WoodCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                CarvedChevrons()
                KnotBox()
                Text(title.uppercased())
                    .font(.system(.headline, design: .serif).weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(LinearGradient(colors: [Palette.brassLight, Palette.brass], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.6), radius: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                KnotBox()
                CarvedChevrons().scaleEffect(x: -1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.22)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.brass.opacity(0.5), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.35), lineWidth: 1).padding(2))
                .padding([.horizontal, .bottom], 12)
        }
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(ImagePaint(image: Image(Art.darkWoodAcross), scale: 0.5))
                .overlay(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.55, green: 0.22, blue: 0.08).opacity(0.28)))
                .overlay(RoundedRectangle(cornerRadius: 10).fill(
                    LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.brassDark, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.45), radius: 7, y: 5)
        }
        .overlay {
            GeometryReader { g in
                ForEach(0..<4, id: \.self) { i in
                    BrassPlate().position(x: i % 2 == 0 ? 9 : g.size.width - 9, y: i < 2 ? 9 : g.size.height - 9)
                }
            }
        }
        .padding(4)
    }
}

/// One choice from a few, as bevelled chips: the chosen one is gold, the others dark wood in a brass rim.
struct WoodChips<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    /// Accessibility identifier of each chip.
    let id: (Value) -> String

    var body: some View {
        // Short labels (numbers) are set large; long ones (Intermediate, Ghana Classic) smaller, so a
        // row never has to shrink them unreadably.
        let longest = options.map { label($0).count }.max() ?? 0
        let font: Font.TextStyle = longest <= 3 ? .title3 : .body
        // Up to three in a row; four (the levels) in two rows of two, so every name is set full size.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: options.count > 3 ? 2 : options.count)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.self) { option in
                let chosen = option == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(font, design: .serif).weight(chosen ? .bold : .medium))
                        .foregroundStyle(chosen ? Palette.night : Palette.ivory)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().fill(chosen
                            ? LinearGradient(colors: [Palette.brassLight, Palette.brass], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)))
                        .overlay(Capsule().stroke(.white.opacity(chosen ? 0.45 : 0.08), lineWidth: 1).padding(2))
                        .overlay(Capsule().stroke(chosen ? Palette.brassDark : Palette.brass.opacity(0.8), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier(id(option))
            }
        }
    }
}

/// The big gold button that starts a game.
struct BrassButton: View {
    let title: String
    let systemImage: String
    /// Smaller, for inside a lesson card.
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage).font(.system(size: compact ? 18 : 26, weight: .bold))
                Text(title).font(.system(compact ? .title3 : .title, design: .serif).weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
                .foregroundStyle(Palette.night)
                .shadow(color: .white.opacity(0.35), radius: 0, y: 1)
                .frame(maxWidth: .infinity, minHeight: compact ? 48 : 68)
                .background(Capsule().fill(LinearGradient(
                    colors: [Palette.brassLight, Palette.brass, Palette.brassDark], startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1).padding(3))
                .overlay(Capsule().stroke(Palette.night.opacity(0.6), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.45), radius: 5, y: 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A line of small print between two brass rules, under a panel's button.
struct RuledNote: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Palette.brass.opacity(0.6)).frame(minWidth: 12, maxHeight: 1)
            Text(text)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Palette.ivory.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Rectangle().fill(Palette.brass.opacity(0.6)).frame(minWidth: 12, maxHeight: 1)
        }
    }
}

/// A switch on wood: ivory label, brass when on.
struct WoodToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(.body, design: .serif).weight(.medium))
                .foregroundStyle(Palette.ivory)
        }
        .toggleStyle(KnotToggleStyle())
    }
}

/// One of a few, on a single wooden track: the chosen one is a gold pill (the rules preset).
struct WoodSegmented<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    let id: (Value) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let chosen = option == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(.body, design: .serif).weight(chosen ? .bold : .semibold))
                        .foregroundStyle(chosen ? Palette.night : Palette.ivory)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background {
                            if chosen {
                                Capsule().fill(LinearGradient(colors: [Palette.brassLight, Palette.brass], startPoint: .top, endPoint: .bottom))
                                    .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 1).padding(2))
                                    .overlay(Capsule().stroke(Palette.brassDark, lineWidth: 1.5))
                                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier(id(option))
            }
        }
        .padding(3)
        .background(Capsule().fill(.black.opacity(0.35)))
        .overlay(Capsule().stroke(Palette.brass.opacity(0.8), lineWidth: 1.5))
    }
}

/// A switch carved for the game: a green track when on, dark wood when off, and a brass knot that slides.
struct KnotToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { configuration.isOn.toggle() }
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 12)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn
                              ? LinearGradient(colors: [Palette.color(.green).opacity(0.85), Palette.color(.green)], startPoint: .top, endPoint: .bottom)
                              : LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().stroke(Palette.brass.opacity(0.8), lineWidth: 1.5))
                        .frame(width: 64, height: 34)
                    ZStack {
                        Circle().fill(RadialGradient(colors: [Palette.brassLight, Palette.brass, Palette.brassDark],
                                                     center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 20))
                        Circle().stroke(Palette.brassDark, lineWidth: 1)
                        Image(systemName: "command").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.brassDark)
                    }
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .padding(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A row in a settings card, with a thin rule under it (none under the last).
struct WoodRow<Content: View>: View {
    var divider = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content.padding(.vertical, 8)
            if divider { Rectangle().fill(Palette.brass.opacity(0.35)).frame(height: 1) }
        }
    }
}
