import SwiftUI

/// The password screen. A known password signs in; a new one goes on to the first photo.
struct AuthView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var showsPassword = false
    @State private var fieldError: String?
    @State private var busy = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                header
                form
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { StatusBarMask() }
        .onChange(of: password) { fieldError = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Wordmark()
                .accessibilityAddTraits(.isHeader)
            Text("Введи свой пароль — или придумай новый, и появится новый аккаунт.")
                .font(.body)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            FormField(label: "Пароль", error: fieldError) {
                HStack(spacing: 8) {
                    passwordInput
                    revealButton
                }
                // The field and the eye button stay two VoiceOver stops with their own labels.
                .accessibilityElement(children: .contain)
            }

            Text("Логина нет: пароль и есть аккаунт. Запомни его — с ним ты войдёшь на любом телефоне.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if AppConfig.isDemo {
                Label("Демо: пароль 1234 — готовый аккаунт «барсук», любой другой — новый аккаунт.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: submit) {
                ButtonLabel(title: "Войти", isLoading: busy)
            }
            .buttonStyle(LocketButtonStyle(.primary))
            .disabled(busy)
        }
    }

    @ViewBuilder
    private var passwordInput: some View {
        if showsPassword {
            inputTraits(TextField("Пароль", text: $password, prompt: prompt))
        } else {
            inputTraits(SecureField("Пароль", text: $password, prompt: prompt))
        }
    }

    private var prompt: Text {
        Text.placeholder("Не короче 4\(nbsp)символов")
    }

    private func inputTraits<Input: View>(_ input: Input) -> some View {
        input
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($passwordFocused)
            .onSubmit(submit)
            // FormField puts its error in the hint; the container above keeps it off the field.
            .accessibilityHint(fieldError ?? "")
    }

    private var revealButton: some View {
        Button {
            let wasFocused = passwordFocused
            showsPassword.toggle()
            // Swapping SecureField for TextField drops the keyboard; bring it back.
            if wasFocused { passwordFocused = true }
        } label: {
            Image(systemName: showsPassword ? "eye.slash" : "eye")
                .font(.body)
                .foregroundStyle(Palette.muted)
                .frame(width: Space.hitTarget, height: Space.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsPassword ? "Скрыть пароль" : "Показать пароль")
    }

    private func submit() {
        guard !busy else { return }
        if let problem = validationError {
            show(problem)
            passwordFocused = true
            return
        }
        fieldError = nil
        busy = true
        let typed = password
        Task {
            defer { busy = false }
            do {
                try await model.submitPassword(typed)
            } catch is CancellationError {
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    /// Spaces count: the server keeps the password exactly as typed.
    private var validationError: String? {
        if password.isEmpty { return "Введи пароль" }
        if password.count < 4 { return "Пароль — минимум 4\(nbsp)символа" }
        return nil
    }

    private func show(_ message: String) {
        fieldError = message
        AccessibilityNotification.Announcement(message).post()
    }
}

/// A new password: the account is created together with its first photo.
struct FirstPhotoView: View {
    let password: String

    var body: some View {
        CameraScreen(purpose: .firstPhoto(password: password))
    }
}

/// After the first photo: one of three usernames. There is no field, so no two people pick the same.
struct UsernamePickerView: View {
    private enum Loading: Equatable {
        case idle, loading, loaded, failed(String)
    }

    @Environment(AppModel.self) private var model
    @State private var suggestions: [UsernameSuggestion] = []
    @State private var loading: Loading = .idle
    @State private var selected: String?
    @State private var choiceError: String?
    @State private var choosing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                ScreenTitle(
                    title: "Юзернейм",
                    subtitle: "По нему тебя найдут друзья. Свой вписать нельзя — выбери один из трёх."
                )
                VStack(alignment: .leading, spacing: 12) {
                    list
                    if let choiceError {
                        errorLine(choiceError)
                    }
                }
                actions
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.gap)
            .padding(.bottom, Space.section)
        }
        .safeAreaInset(edge: .top, spacing: 0) { StatusBarMask() }
        .task {
            if suggestions.isEmpty { await load() }
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private var list: some View {
        if case .failed(let message) = loading {
            InlineError(message: "Не удалось загрузить варианты. \(message)") {
                Task { await load() }
            }
        } else if suggestions.isEmpty {
            skeleton
        } else {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(suggestions) { suggestion in
                        row(suggestion)
                    }
                }
            }
            // Dimmed while new suggestions are on their way.
            .opacity(loading == .loading ? 0.5 : 1)
            .disabled(loading == .loading || choosing)
        }
    }

    private func row(_ suggestion: UsernameSuggestion) -> some View {
        let isSelected = suggestion.username == selected
        return Button {
            selected = suggestion.username
            choiceError = nil
        } label: {
            HStack(spacing: 12) {
                // A control, not data: white, not the accent.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.text : Palette.faint)
                    .accessibilityHidden(true)
                Text(suggestion.username)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text(kindTitle(suggestion.kind))
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            .frame(minHeight: Space.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var skeleton: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 12) {
                        SkeletonBlock(width: 24, height: 24, cornerRadius: 12)
                        SkeletonBlock(width: 140, height: 22)
                        Spacer(minLength: 12)
                        SkeletonBlock(width: 56, height: 16)
                    }
                    .frame(minHeight: Space.hitTarget)
                }
            }
        }
        .appearsAfter()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Загружаю варианты…")
    }

    private func errorLine(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(Palette.negative)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: choose) {
                ButtonLabel(title: chooseTitle, isLoading: choosing)
            }
            .buttonStyle(LocketButtonStyle(.primary))
            .disabled(choosing || loading == .loading)

            Button {
                choiceError = nil
                Task { await load() }
            } label: {
                ButtonLabel(title: "Другие варианты", isLoading: loading == .loading && !suggestions.isEmpty)
            }
            .buttonStyle(LocketButtonStyle(.secondary))
            .disabled(choosing || loading == .loading)
        }
    }

    private var chooseTitle: String {
        if let selected { return "Выбрать «\(selected)»" }
        return "Выбрать"
    }

    private func kindTitle(_ kind: UsernameSuggestion.Kind) -> String {
        switch kind {
        case .animal: return "животное"
        case .swear: return "мат"
        case .name: return "имя"
        }
    }

    // MARK: - Actions

    private func load() async {
        guard loading != .loading else { return }
        loading = .loading
        do {
            let fresh = try await model.usernameSuggestions()
            selected = nil
            if fresh.isEmpty {
                suggestions = []
                loading = .failed("Сервер не прислал вариантов. Попробуй ещё раз.")
            } else {
                suggestions = fresh
                loading = .loaded
            }
        } catch is CancellationError {
            loading = suggestions.isEmpty ? .idle : .loaded
        } catch {
            loading = .failed(error.localizedDescription)
        }
    }

    private func choose() {
        guard !choosing else { return }
        guard let username = selected else {
            show("Выбери один из трёх")
            return
        }
        choiceError = nil
        choosing = true
        Task {
            defer { choosing = false }
            do {
                try await model.chooseUsername(username)
            } catch is CancellationError {
            } catch {
                show(error.localizedDescription)
                if isServerRefusal(error) {
                    await recoverFromRefusal()
                }
            }
        }
    }

    /// Taken a moment ago, or already chosen (a lost reply): moves on if the account has a
    /// username by now, otherwise offers fresh suggestions. The error stays under the list.
    private func recoverFromRefusal() async {
        await model.refreshMe()
        guard model.phase == .needsUsername else { return }
        await load()
    }

    /// The server answered with a reason; a dropped connection is not one, so the list stays.
    private func isServerRefusal(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        switch apiError {
        case .server: return true
        case .unauthorized, .offline: return false
        }
    }

    private func show(_ message: String) {
        choiceError = message
        AccessibilityNotification.Announcement(message).post()
    }
}

/// Keeps scrolled content from showing under the status bar.
private struct StatusBarMask: View {
    var body: some View {
        Color.clear
            .frame(height: 0)
            .background(Palette.ground, ignoresSafeAreaEdges: .top)
    }
}

private extension Text {
    /// A field's placeholder: an example value in the faint meta tone.
    static func placeholder(_ example: String) -> Text {
        Text(example).foregroundStyle(Palette.faint)
    }
}
