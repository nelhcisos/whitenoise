import SwiftUI

/// Sign in or sign up: the wordmark, one sentence about the app, then the form.
struct AuthView: View {
    private enum Field: CaseIterable { case name, email, password }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 44
    @State private var isSignUp = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errors: [Field: String] = [:]
    @State private var serverError: String?
    @State private var busy = false
    @FocusState private var focus: Field?

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
        .onChange(of: isSignUp) {
            errors = [:]
            serverError = nil
        }
        .onChange(of: name) { errors[.name] = nil }
        .onChange(of: email) { errors[.email] = nil }
        .onChange(of: password) { errors[.password] = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                LogoMark(size: logoSize)
                Text("Locket")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("Фото для своих. По воскресеньям — итоги недели: лучшее фото и друг недели.")
                .font(.body)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            Picker("Режим", selection: reduceMotion ? $isSignUp : $isSignUp.animation(.snappy)) {
                Text("Вход").tag(false)
                Text("Регистрация").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(busy)

            if isSignUp {
                FormField(label: "Имя", error: errors[.name]) {
                    TextField("Имя", text: $name, prompt: Text.placeholder("Например, Маша"))
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .name)
                        .onSubmit { focus = .email }
                }
            }

            FormField(label: "Email", error: errors[.email]) {
                TextField("Email", text: $email, prompt: Text.placeholder("Например, masha@mail.ru"))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
            }

            FormField(label: "Пароль", error: errors[.password]) {
                SecureField("Пароль", text: $password, prompt: Text.placeholder("Не короче 6\(nbsp)символов"))
                    .textContentType(isSignUp ? .newPassword : .password)
                    .submitLabel(.done)
                    .focused($focus, equals: .password)
                    .onSubmit(submit)
            }

            if let serverError {
                Label {
                    Text(serverError)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Palette.negative)
                }
                .font(.subheadline)
            }

            Button(action: submit) {
                ButtonLabel(title: isSignUp ? "Создать аккаунт" : "Войти", isLoading: busy)
            }
            .buttonStyle(LocketButtonStyle(.primary))
            .disabled(busy)
        }
    }

    private func submit() {
        guard !busy else { return }
        serverError = nil
        errors = validationErrors()
        if let first = Field.allCases.first(where: { errors[$0] != nil }) {
            focus = first
            if let message = errors[first] {
                AccessibilityNotification.Announcement(message).post()
            }
            return
        }
        focus = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                if isSignUp {
                    try await model.signUp(name: name, email: email, password: password)
                } else {
                    try await model.signIn(email: email, password: password)
                }
            } catch {
                serverError = error.localizedDescription
                AccessibilityNotification.Announcement(error.localizedDescription).post()
            }
        }
    }

    private func validationErrors() -> [Field: String] {
        var result: [Field: String] = [:]
        if isSignUp && name.isBlank {
            result[.name] = "Укажи имя — его увидят друзья"
        }
        if email.isBlank {
            result[.email] = "Укажи email"
        } else if !emailLooksValid {
            result[.email] = "Проверь email: нужен адрес вида masha@mail.ru"
        }
        if password.isEmpty {
            result[.password] = "Введи пароль"
        } else if password.count < 6 {
            result[.password] = "Пароль — не короче 6\(nbsp)символов"
        }
        return result
    }

    private var emailLooksValid: Bool {
        let parts = email.trimmingCharacters(in: .whitespaces).split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
    }
}

/// The step after signing up: join a company by its invite code or create a new one.
struct CircleSetupView: View {
    private enum Field { case code, circleName }
    private enum Action { case join, create }

    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var circleName = ""
    @State private var errors: [Field: String] = [:]
    @State private var running: Action?
    @State private var confirmingSignOut = false
    @FocusState private var focus: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                ScreenTitle(title: "Компания", subtitle: greeting)
                joinSection
                createSection
                Button("Выйти из аккаунта…") { confirmingSignOut = true }
                    .buttonStyle(LocketButtonStyle(.destructive))
                    .disabled(running != nil)
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: code) { errors[.code] = nil }
        .onChange(of: circleName) { errors[.circleName] = nil }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                Task { await model.signOut() }
            }
        } message: {
            Text("Войти снова можно с тем же email и паролем.")
        }
    }

    private var greeting: String {
        let name = model.me?.user.name ?? "друг"
        return "Привет, \(name). Locket работает внутри компании друзей: все видят фото друг друга и оценивают их, а в воскресенье подводятся итоги."
    }

    private var joinSection: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            sectionHeader("Вступить по коду", hint: "Попроси код у друга — он во вкладке «Друзья».")
            FormField(label: "Код приглашения", error: errors[.code]) {
                TextField("Код приглашения", text: $code, prompt: Text.placeholder("Например, K7QX2M"))
                    .font(.body.monospaced())
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .focused($focus, equals: .code)
                    .onSubmit(join)
            }
            Button(action: join) {
                ButtonLabel(title: "Вступить", isLoading: running == .join)
            }
            .buttonStyle(LocketButtonStyle(.primary))
            .disabled(running != nil)
        }
    }

    private var createSection: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            sectionHeader("Создать компанию", hint: "Получишь код, который можно отправить друзьям.")
            FormField(label: "Название", error: errors[.circleName]) {
                TextField("Название", text: $circleName, prompt: Text.placeholder("Например, Банда"))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($focus, equals: .circleName)
                    .onSubmit(create)
            }
            Button(action: create) {
                ButtonLabel(title: "Создать компанию", isLoading: running == .create)
            }
            .buttonStyle(LocketButtonStyle(.secondary))
            .disabled(running != nil)
        }
    }

    private func sectionHeader(_ title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title)
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func join() {
        guard running == nil else { return }
        let symbols = code.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if symbols.count != 6 {
            show(code.isBlank ? "Введи код приглашения" : "Код — 6\(nbsp)латинских букв и цифр, например K7QX2M", at: .code)
            focus = .code
            return
        }
        focus = nil
        running = .join
        Task {
            defer { running = nil }
            do {
                try await model.joinCircle(code: code)
            } catch {
                show(error.localizedDescription, at: .code)
            }
        }
    }

    private func create() {
        guard running == nil else { return }
        if circleName.isBlank {
            show("Придумай название — его увидят друзья", at: .circleName)
            focus = .circleName
            return
        }
        focus = nil
        running = .create
        Task {
            defer { running = nil }
            do {
                try await model.createCircle(name: circleName)
            } catch {
                show(error.localizedDescription, at: .circleName)
            }
        }
    }

    private func show(_ message: String, at field: Field) {
        errors[field] = message
        AccessibilityNotification.Announcement(message).post()
    }
}

private extension Text {
    /// A field's placeholder: an example value in the faint meta tone.
    static func placeholder(_ example: String) -> Text {
        Text(example).foregroundStyle(Palette.faint)
    }
}
