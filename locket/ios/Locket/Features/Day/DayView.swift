import SwiftUI

/// «День»: rate today like a ride (1–5 stars, then what got in the way or what you liked),
/// yesterday, recent days, what helps after a weak day, and when the evening reminder comes.
/// Ratings are private: only you see them.
struct DayView: View {
    @Environment(AppModel.self) private var model
    @State private var editingYesterday = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.gap) {
                    ScreenTitle(title: "День", subtitle: subtitle)
                    if case .failed(let message) = model.daysState {
                        InlineError(message: "Не удалось загрузить оценки. \(message)") {
                            Task { await model.refreshDays() }
                        }
                    }
                    DayEditor(key: todayKey, title: "Сегодня")
                }
                yesterday
                solutions
                if !olderDays.isEmpty {
                    history
                }
                ReminderSection()
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.gap)
            .padding(.bottom, Space.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.ground)
        .safeAreaInset(edge: .top, spacing: 0) {
            // Keeps scrolled content from showing under the status bar.
            Color.clear
                .frame(height: 0)
                .background(Palette.ground, ignoresSafeAreaEdges: .top)
        }
        .refreshable { await model.refreshDays() }
        .task { await model.refreshDays() }
        .sheet(isPresented: $editingYesterday) {
            NavigationStack {
                ScrollView {
                    DayEditor(key: yesterdayKey, title: "Вчера")
                        .padding(Space.margin)
                }
                .background(Palette.ground)
                .navigationTitle("Вчера")
                .navigationBarTitleDisplayMode(.inline)
                .groundBar(for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { editingYesterday = false }
                    }
                }
            }
            .environment(model)
        }
    }

    // MARK: - Dates

    private var todayKey: String { DayRating.key(for: Date()) }

    private var yesterdayKey: String {
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-86_400)
        return DayRating.key(for: date)
    }

    private var subtitle: String {
        if let today = model.day(todayKey) {
            return "Сегодня — \(today.stars)\(nbsp)из\(nbsp)5. Оценки видишь только ты."
        }
        return "Оцени, как прошёл день, — как поездку. Каждый вечер в \(DayReminder.timeText) придёт напоминание."
    }

    private var olderDays: [DayRating] {
        Array(model.days.filter { $0.date < yesterdayKey }.prefix(14))
    }

    // MARK: - Sections

    private var yesterday: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader(title: "Вчера") {
                Button(model.day(yesterdayKey) == nil ? "Оценить…" : "Изменить…") { editingYesterday = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .frame(minHeight: Space.hitTarget)
            }
            if let day = model.day(yesterdayKey) {
                Card {
                    DayRow(day: day)
                }
            } else {
                Text("Вчера без оценки — его ещё можно оценить.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private var solutions: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader("Решения")
            Card {
                ForEach(Array(DaySolution.allCases.enumerated()), id: \.element.id) { index, solution in
                    if index > 0 {
                        Rectangle().fill(Palette.border).frame(height: 1).accessibilityHidden(true)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: solution.symbol)
                            .font(.title3)
                            .foregroundStyle(Palette.muted)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(solution.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Palette.text)
                            Text(solution.hint)
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader("Последние дни")
            Card {
                ForEach(Array(olderDays.enumerated()), id: \.element.id) { index, day in
                    if index > 0 {
                        Rectangle().fill(Palette.border).frame(height: 1).accessibilityHidden(true)
                    }
                    DayRow(day: day, showsDate: true)
                }
            }
        }
    }
}

/// One rated day: the stars and what got in the way or what you liked.
private struct DayRow: View {
    let day: DayRating
    var showsDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsDate {
                Text(DayRating.title(of: day.date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
            }
            (Text(String(repeating: "★", count: day.stars)).foregroundStyle(Palette.accent)
                + Text(String(repeating: "★", count: max(0, 5 - day.stars))).foregroundStyle(Palette.border))
                .font(.body)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var summary: String {
        if day.stars == 5 {
            return day.liked.isEmpty ? "Отличный день" : day.liked.map(\.title).joined(separator: ", ")
        }
        return day.reasons.isEmpty ? "Причины не отмечены" : day.reasons.map(\.title).joined(separator: ", ")
    }

    private var spoken: String {
        let date = showsDate ? DayRating.title(of: day.date) + ", " : ""
        return "\(date)\(day.stars) из 5. \(summary)"
    }
}

/// Today's (or yesterday's) form: saves itself shortly after each change.
private struct DayEditor: View {
    @Environment(AppModel.self) private var model
    let key: String
    let title: String

    private enum SaveStatus: Equatable {
        case idle, saving, saved, failed(String)
    }

    @State private var draft: DayRating
    @State private var dirty = false
    @State private var status: SaveStatus = .idle
    @State private var saveTask: Task<Void, Never>?

    init(key: String, title: String) {
        self.key = key
        self.title = title
        _draft = State(initialValue: DayRating.blank(key))
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(DayRating.title(of: key))
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            DayRatingForm(rating: $draft, onChange: { changed() })
            statusLine
        }
        .onAppear { load() }
        .onChange(of: model.days) { _, _ in
            if !dirty { load() }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .failed(let message):
            Label("Не сохранилось: \(message)", systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Palette.negative)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            Text(draft.stars == 0 ? "Как поездку: от 1 до 5 звёзд" : "Оценка сохранена")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        case .saving:
            Text("Сохраняю…")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        case .saved:
            Text("Оценка сохранена")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
    }

    private func load() {
        draft = model.day(key) ?? DayRating.blank(key)
    }

    private func changed() {
        guard draft.stars > 0 else { return }
        dirty = true
        saveTask?.cancel()
        status = .saving
        let rating = draft
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            do {
                try await model.saveDay(rating)
                if Task.isCancelled { return }
                status = .saved
                dirty = false
            } catch is CancellationError {
            } catch {
                if Task.isCancelled { return }
                status = .failed(error.localizedDescription)
            }
        }
    }
}

/// When the evening notification comes, and a way to try it right now.
private struct ReminderSection: View {
    @Environment(AppModel.self) private var model
    @State private var enabled = DayReminder.isEnabled
    @State private var minutes = DayReminder.minutes
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader("Напоминание")
            Card {
                Toggle("Каждый вечер", isOn: $enabled)
                    .font(.body)
                    .foregroundStyle(Palette.text)
                    .tint(Palette.positive)
                    .frame(minHeight: Space.hitTarget)
                if enabled {
                    DatePicker("Время", selection: time, displayedComponents: .hourAndMinute)
                        .font(.body)
                        .foregroundStyle(Palette.text)
                        .frame(minHeight: Space.hitTarget)
                }
                Text("Придёт на экран блокировки: удерживай уведомление и ставь звёзды, не открывая приложение.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await sendTest() }
                } label: {
                    ButtonLabel(title: "Проверить уведомление", isLoading: sending)
                }
                .buttonStyle(LocketButtonStyle(.secondary))
                .disabled(sending)
            }
        }
        .onChange(of: enabled) { _, value in
            DayReminder.isEnabled = value
            Task { await DayReminder.schedule() }
        }
        .onChange(of: minutes) { _, value in
            DayReminder.minutes = value
            Task { await DayReminder.schedule() }
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (parts.hour ?? 23) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func sendTest() async {
        sending = true
        defer { sending = false }
        if await DayReminder.sendTest() {
            model.show(toast: "Через 5\(nbsp)секунд придёт уведомление — заблокируй телефон и удерживай его")
        } else {
            model.show(error: "Уведомления выключены — разреши их для Locket в Настройках")
        }
    }
}
