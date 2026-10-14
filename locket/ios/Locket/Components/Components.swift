import SwiftUI

struct Avatar: View {
    let name: String
    var size: CGFloat = 40

    private static let palette: [Color] = [
        .locketYellow, .orange, .pink, .mint, .cyan, Color(red: 0.75, green: 0.6, blue: 1.0), .green,
    ]

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
    }

    private var color: Color {
        // Stable across launches, unlike hashValue.
        let seed = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Self.palette[abs(seed) % Self.palette.count]
    }
}

/// Square photo that fills its container. Put it in an overlay of a sized view.
struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                ZStack {
                    Color.card
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                }
            default:
                ZStack {
                    Color.card
                    ProgressView()
                }
            }
        }
    }
}

struct SquarePhoto: View {
    let url: URL?
    var cornerRadius: CGFloat = 36

    var body: some View {
        Color.card
            .aspectRatio(1, contentMode: .fit)
            .overlay { RemoteImage(url: url) }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct LogoMark: View {
    var size: CGFloat = 88

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color.locketYellow)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.black)
            }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration)
    }

    private struct PrimaryButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.locketYellow, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }
}

extension View {
    func locketField() -> some View {
        padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
