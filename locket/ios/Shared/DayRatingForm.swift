import SwiftUI

/// «Оцени свой день, как поездку»: 1–5 stars, then what got in the way (below five)
/// or what you liked most (five), two yes/no questions and, after a weak day, what helps.
/// Used on the lock-screen card and in the app's «День» tab, so it draws no background
/// of its own and uses the primary/secondary styles that work on the system material too.
struct DayRatingForm: View {
    @Binding var rating: DayRating
    /// Called after every change the person makes.
    var onChange: @MainActor () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            stars
            if (1...4).contains(rating.stars) {
                section("Что помешало дню стать твоим?") {
                    ForEach(DayReason.allCases) { reason in
                        chip(reason.title, selected: rating.reasons.contains(reason)) { toggle(reason) }
                    }
                }
            } else if rating.stars == 5 {
                section("Что понравилось больше всего?") {
                    ForEach(DayHighlight.allCases) { highlight in
                        chip(highlight.title, selected: rating.liked.contains(highlight)) { toggle(highlight) }
                    }
                }
            }
            if rating.stars > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    question("В хорошей форме?", answer: rating.condition) { rating.condition = $0 }
                    question("В хорошем месте?", answer: rating.place) { rating.place = $0 }
                }
            }
            if (1...3).contains(rating.stars) {
                solutions
            }
        }
    }

    // MARK: - Parts

    private var stars: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { value in
                let lit = value <= rating.stars
                Button {
                    rating.stars = value
                    onChange()
                } label: {
                    Image(systemName: lit ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(lit ? Palette.accent : Color.secondary)
                        .frame(width: Space.hitTarget, height: Space.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) из 5")
                .accessibilityAddTraits(value == rating.stars ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Оценка дня")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 8) {
                content()
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: Space.hitTarget)
                .background(selected ? Palette.accentTint : Palette.systemFill, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Palette.accent : Color.clear, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func question(_ title: String, answer: Bool?, set: @escaping (Bool?) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Tapping the chosen answer again clears it.
            chip("Нет", selected: answer == false) {
                set(answer == false ? nil : false)
                onChange()
            }
            chip("Да", selected: answer == true) {
                set(answer == true ? nil : true)
                onChange()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var solutions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Завтра попробуй")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(DaySolution.allCases.map(\.title).joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Changes

    private func toggle(_ reason: DayReason) {
        if let index = rating.reasons.firstIndex(of: reason) {
            rating.reasons.remove(at: index)
        } else {
            rating.reasons.append(reason)
        }
        onChange()
    }

    private func toggle(_ highlight: DayHighlight) {
        if let index = rating.liked.firstIndex(of: highlight) {
            rating.liked.remove(at: index)
        } else {
            rating.liked.append(highlight)
        }
        onChange()
    }
}

/// Lays children out left to right and wraps to the next line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    private struct Item {
        let index: Int
        let x: CGFloat
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let x = current.items.isEmpty ? 0 : current.width + spacing
            if !current.items.isEmpty && x + size.width > width {
                rows.append(current)
                let y = current.y + current.height + spacing
                current = Row()
                current.y = y
                current.items.append(Item(index: index, x: 0, size: size))
                current.width = size.width
                current.height = size.height
            } else {
                current.items.append(Item(index: index, x: x, size: size))
                current.width = x + size.width
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
