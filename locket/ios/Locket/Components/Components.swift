import SwiftUI

// Shared building blocks. Every screen is made of these and the tokens in Theme.swift;
// see DESIGN.md for when to use which.

// MARK: - People and photos

/// A person's stable initial on a dark tint of their own hue. Identity, not data:
/// the hues stay muted and never reuse the accent's yellow.
struct Avatar: View {
    let name: String
    var size: CGFloat = 40

    /// Hues at least 60° apart, skipping yellow (the accent) and violet.
    private static let hues: [Double] = [10, 95, 160, 205, 330]

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color(hue: hue, saturation: 0.35, brightness: 0.95))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hue: hue, saturation: 0.55, brightness: 0.32)))
            .accessibilityHidden(true)
    }

    private var hue: Double {
        // Stable across launches, unlike hashValue.
        let seed = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Self.hues[abs(seed) % Self.hues.count] / 360
    }
}

/// A photo that fills its container. Put it in an overlay of a sized view.
/// Loading is a flat raised field (no spinner); a failed load says so.
struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                ZStack {
                    Palette.raised
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(Palette.faint)
                }
                .accessibilityLabel("Фото не загрузилось")
            default:
                Palette.raised
            }
        }
    }
}

struct SquarePhoto: View {
    let url: URL?
    var cornerRadius: CGFloat = Radius.photo

    var body: some View {
        Palette.raised
            .aspectRatio(1, contentMode: .fit)
            .overlay { RemoteImage(url: url) }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The product's mark: a flat yellow tile with a heart.
struct LogoMark: View {
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Palette.accent)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(Palette.onFill)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Titles and sections

/// The screen's h1 and, optionally, one sentence about its data (the finding, the period).
struct ScreenTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title.bold())
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section heading with an optional trailing text action ("Все", "Изменить…").
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

/// A flat card: one tone step above the ground, no border, no shadow.
struct Card<Content: View>: View {
    var padding: CGFloat = Space.cardPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

// MARK: - States

/// An error inside the block that failed: what happened, how to get out, a Retry.
struct InlineError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Palette.negative)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Повторить", action: retry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)
                .frame(minHeight: Space.hitTarget)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

/// An empty block keeps its frame: one sentence and, when there is one, the next step.
struct EmptyState: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .font(.body)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(LocketButtonStyle(.secondary))
            }
        }
        .padding(Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

/// A loading placeholder at the real size of what it stands for. Flat, no shimmer.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Palette.raised)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Shows loading placeholders only if loading takes longer than `delay`,
    /// so fast responses don't flash a skeleton.
    func appearsAfter(_ delay: Duration = .milliseconds(250)) -> some View {
        modifier(AppearsAfter(delay: delay))
    }
}

private struct AppearsAfter: ViewModifier {
    let delay: Duration
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .task {
                try? await Task.sleep(for: delay)
                visible = true
            }
    }
}

// MARK: - Buttons and fields

/// Buttons. `.primary` is the inverted white fill; `.accent` is the yellow fill and is
/// used for the screen's one accent control only (the camera's send); `.secondary` is outlined.
struct LocketButtonStyle: ButtonStyle {
    enum Kind { case primary, accent, secondary, destructive }

    let kind: Kind
    var fullWidth = true

    init(_ kind: Kind, fullWidth: Bool = true) {
        self.kind = kind
        self.fullWidth = fullWidth
    }

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, fullWidth: fullWidth)
    }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 20)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(minHeight: Space.controlHeight)
                .background(fill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay {
                    if kind == .secondary || kind == .destructive {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(configuration.isPressed ? Palette.muted : Palette.control, lineWidth: 1)
                    }
                }
                .opacity(configuration.isPressed && (kind == .primary || kind == .accent) ? 0.85 : 1)
                .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }

        private var foreground: Color {
            guard isEnabled else { return Palette.faint }
            switch kind {
            case .primary, .accent: return Palette.onFill
            case .secondary: return Palette.text
            case .destructive: return Palette.negative
            }
        }

        private var fill: Color {
            guard isEnabled else { return Palette.raised }
            switch kind {
            case .primary: return Palette.text
            case .accent: return Palette.accent
            case .secondary, .destructive: return configuration.isPressed ? Palette.raised : Palette.surface
            }
        }
    }
}

/// A button label that keeps its words while the request runs, with a spinner in front.
struct ButtonLabel: View {
    let title: String
    var isLoading = false

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Palette.faint)
            }
            Text(title)
        }
    }
}

/// A form field with its label above and its error right under it.
struct FormField<Field: View>: View {
    let label: String
    var error: String?
    @ViewBuilder var field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)
            field()
                .font(.body)
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 16)
                .frame(minHeight: Space.controlHeight)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(error == nil ? Palette.border : Palette.negative, lineWidth: 1)
                )
                .accessibilityLabel(label)
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
