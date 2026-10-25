import SwiftUI

/// At the top of the feed after a few of your own photos: when is your birthday?
/// «Не сейчас» puts it off for a month (the server remembers).
struct BirthdayPrompt: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            Card {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Когда у тебя день рождения?")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Друзьям придёт напоминание за месяц, за 5 дней и в сам день — и твой виш-лист. Год не нужен.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { buttons }
                    VStack(alignment: .leading, spacing: 8) { buttons }
                }
            }
            .sheet(isPresented: $picking) {
                BirthdayPicker()
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button {
            picking = true
        } label: {
            Label("Указать дату", systemImage: "birthday.cake")
        }
        .buttonStyle(LocketButtonStyle(.secondary, fullWidth: false))
        Button("Не сейчас") {
            dismissed = true
            Task { await model.askBirthdayLater() }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(Palette.muted)
        .frame(minHeight: Space.hitTarget)
    }
}

/// Day and month on two wheels; the year is never asked. Saving tells the server,
/// which reminds friends a month before, 5 days before and on the day.
struct BirthdayPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var day = 1
    @State private var month = 1
    @State private var started = false
    @State private var saving = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.gap) {
                    ScreenTitle(
                        title: "День рождения",
                        subtitle: "Друзьям придёт напоминание за месяц, за 5 дней и в сам день — с твоим виш-листом. Год не нужен."
                    )
                    HStack(spacing: 0) {
                        Picker("День", selection: $day) {
                            ForEach(Array(1...Birthday.days(in: month)), id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        Picker("Месяц", selection: $month) {
                            ForEach(Array(1...12), id: \.self) { value in
                                Text(Birthday.months[value - 1]).tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: month) { _, newMonth in
                        day = min(day, Birthday.days(in: newMonth))
                    }
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Palette.negative)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        Task { await save() }
                    } label: {
                        ButtonLabel(title: saving ? "Сохраняю…" : "Сохранить", isLoading: saving)
                    }
                    .buttonStyle(LocketButtonStyle(.primary))
                    .disabled(saving)
                    if model.birthday != nil {
                        Button {
                            Task { await clear() }
                        } label: {
                            Text("Убрать дату")
                        }
                        .buttonStyle(LocketButtonStyle(.destructive))
                        .disabled(saving)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.gap)
                .padding(.bottom, Space.section)
            }
            .background(Palette.ground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .groundBar(for: .navigationBar)
            .interactiveDismissDisabled(saving)
            .onAppear {
                // Starts on the date already given, if any.
                guard !started else { return }
                started = true
                if let current = model.birthday {
                    month = current.month
                    day = current.day
                }
            }
        }
    }

    private func save() async {
        await run(failurePrefix: "Не сохранилось") {
            try await model.setBirthday(Birthday(month: month, day: day))
        }
    }

    private func clear() async {
        await run(failurePrefix: "Не получилось убрать") {
            try await model.clearBirthday()
        }
    }

    private func run(failurePrefix: String, _ work: () async throws -> Void) async {
        saving = true
        failure = nil
        defer { saving = false }
        do {
            try await work()
            dismiss()
        } catch is CancellationError {
            // Signed out.
        } catch {
            failure = "\(failurePrefix): \(error.localizedDescription)"
        }
    }
}
