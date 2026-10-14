import SwiftUI

struct AuthView: View {
    @Environment(AppModel.self) private var model
    @State private var isSignUp = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    private var canSubmit: Bool {
        !busy && email.contains("@") && password.count >= 6 && (!isSignUp || !name.isBlank)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                LogoMark().padding(.top, 48)
                Text("Locket")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                Text("Фото для своих. В конце недели — фото недели и друг недели.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)

                Picker("Режим", selection: $isSignUp.animation()) {
                    Text("Вход").tag(false)
                    Text("Регистрация").tag(true)
                }
                .pickerStyle(.segmented)

                if isSignUp {
                    TextField("Как тебя зовут", text: $name)
                        .textContentType(.givenName)
                        .locketField()
                }
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .locketField()
                SecureField("Пароль (от 6 символов)", text: $password)
                    .textContentType(isSignUp ? .newPassword : .password)
                    .locketField()

                if let error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if busy {
                        ProgressView().tint(.black)
                    } else {
                        Text(isSignUp ? "Создать аккаунт" : "Войти")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if isSignUp {
                try await model.signUp(name: name, email: email, password: password)
            } else {
                try await model.signIn(email: email, password: password)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CircleSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var circleName = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Привет, \(model.me?.user.name ?? "друг")! 👋")
                        .font(.largeTitle.bold())
                    Text("Locket работает внутри компании друзей: все видят фото друг друга, оценивают их 🔥🎨😂, а в воскресенье подводятся итоги недели.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                card(title: "Вступить по коду", subtitle: "Попроси код у друга — он во вкладке «Друзья».") {
                    TextField("Например, K7QX2M", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.monospaced())
                        .locketField()
                    Button("Вступить") {
                        Task { await run { try await model.joinCircle(code: code) } }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(code.filter { $0.isLetter || $0.isNumber }.count < 6 || busy)
                }

                card(title: "Создать компанию", subtitle: "Получишь код, который можно отправить друзьям.") {
                    TextField("Название, например «Банда»", text: $circleName)
                        .locketField()
                    Button("Создать") {
                        Task { await run { try await model.createCircle(name: circleName) } }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(circleName.isBlank || busy)
                }

                if let error {
                    Text(error).font(.subheadline).foregroundStyle(.red)
                }

                Button("Выйти из аккаунта", role: .destructive) {
                    Task { await model.signOut() }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func card<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            content()
        }
        .padding(18)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await work()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
