import SwiftUI
import UserNotifications

/// The circle: how to invite friends (the code is the largest thing on screen), who is in it,
/// notifications, your profile and, last, the ways out.
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var editingName = false
    @State private var editingCircle = false
    @State private var confirmLeave = false
    @State private var confirmSignOut = false
    @State private var leaving = false
    @State private var signingOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                ScreenTitle(title: "Друзья", subtitle: finding)
                if let circle = model.circle {
                    invite(circle)
                    members(circle)
                }
                notifications
                profile
                exits
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.gap)
            .padding(.bottom, Space.section)
        }
        .background(Palette.ground)
        .safeAreaInset(edge: .top, spacing: 0) {
            // Keeps scrolled content from showing under the status bar.
            Color.clear
                .frame(height: 0)
                .background(Palette.ground, ignoresSafeAreaEdges: .top)
        }
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            // Back from Settings, where the switch may have changed.
            if newPhase == .active { Task { await refreshNotificationStatus() } }
        }
        .sheet(isPresented: $editingName) {
            RenameSheet(kind: .name, initialValue: model.me?.user.name ?? "")
        }
        .sheet(isPresented: $editingCircle) {
            RenameSheet(kind: .circle, initialValue: model.circle?.name ?? "")
        }
    }

    /// "«Банда» · 4 человека", or that it's only you so far.
    private var finding: String? {
        guard let circle = model.circle else { return nil }
        let count = model.members.count
        if count <= 1 { return "«\(circle.name)» · пока только ты" }
        let people = Russian.plural(count, "человек", "человека", "человек")
        return "«\(circle.name)» · \(count)\(nbsp)\(people)"
    }

    // MARK: - Invite

    private func invite(_ circle: FriendCircle) -> some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader(title: "Компания") {
                headerAction("Изменить название…") { editingCircle = true }
            }
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Код приглашения")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                    // An identifier, so monospaced; spelled out for VoiceOver.
                    Text(circle.inviteCode)
                        .font(.system(.title, design: .monospaced).weight(.semibold))
                        .kerning(4)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .textSelection(.enabled)
                        .accessibilityLabel(circle.inviteCode.map { String($0) }.joined(separator: " "))
                }
                .accessibilityElement(children: .combine)

                Button("Скопировать код") {
                    UIPasteboard.general.string = circle.inviteCode
                    model.show(toast: "Код скопирован")
                }
                .buttonStyle(LocketButtonStyle(.primary))

                ShareLink(item: "Залетай к нам в Locket «\(circle.name)». Код компании: \(circle.inviteCode)") {
                    Text("Поделиться кодом…")
                }
                .buttonStyle(LocketButtonStyle(.secondary))
            }
        }
    }

    // MARK: - Members

    private func members(_ circle: FriendCircle) -> some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader("В компании")
                .frame(minHeight: Space.hitTarget)
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.members) { member in
                        memberRow(member, isOwner: member.id == circle.ownerId)
                    }
                }
            }
        }
    }

    private func memberRow(_ member: Member, isOwner: Bool) -> some View {
        HStack(spacing: 12) {
            Avatar(name: member.name, size: AvatarSize.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(member))
                    .font(.body)
                    .foregroundStyle(Palette.text)
                if isOwner {
                    Text("создатель")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Space.hitTarget)
        .accessibilityElement(children: .combine)
    }

    private func displayName(_ member: Member) -> String {
        member.id == model.myId ? member.name + " · ты" : member.name
    }

    // MARK: - Notifications

    private var notifications: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader("Уведомления")
                .frame(minHeight: Space.hitTarget)
            Card {
                if let notificationStatus {
                    notificationState(notificationStatus)
                } else {
                    SkeletonBlock(width: 220, height: 22)
                        .appearsAfter()
                }
                Text(lockScreenHint(reactions: ReactionKind.allCases.map(\.emoji).joined(separator: " ")))
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(lockScreenHint(reactions: ReactionKind.allCases.map(\.title).joined(separator: ", ")))
                Text("Добавь виджет Locket на экран «Домой»: там всегда последнее фото друзей и те же звёзды и реакции.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func notificationState(_ status: UNAuthorizationStatus) -> some View {
        switch status {
        case .denied:
            statusLabel("Уведомления выключены", systemImage: "bell.slash")
            Button("Открыть настройки уведомлений") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(LocketButtonStyle(.secondary))
        case .notDetermined:
            statusLabel("Уведомления ещё не включены", systemImage: "bell.slash")
            Button("Включить уведомления") {
                Task {
                    await PushRegistrar.requestPermissionAndRegister()
                    await refreshNotificationStatus()
                }
            }
            .buttonStyle(LocketButtonStyle(.secondary))
        default:
            statusLabel("Уведомления включены", systemImage: "bell")
        }
    }

    private func statusLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(Palette.text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Palette.faint)
        }
        .font(.body)
    }

    /// How to rate from the lock screen; `reactions` are the marks on screen or their names for VoiceOver.
    private func lockScreenHint(reactions: String) -> String {
        "Когда друг выложит фото, удерживай уведомление на экране блокировки — появятся звёзды и реакции \(reactions). Оценка уходит сразу, приложение открывать не нужно."
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await PushRegistrar.authorizationStatus()
    }

    // MARK: - Profile

    private var profile: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader(title: "Профиль") {
                headerAction("Изменить имя…") { editingName = true }
            }
            Card {
                HStack(spacing: 12) {
                    Avatar(name: model.me?.user.name ?? "", size: AvatarSize.regular)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.me?.user.name ?? "")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.text)
                        if let email = model.me?.user.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Exits

    private var exits: some View {
        VStack(spacing: 12) {
            Button {
                confirmLeave = true
            } label: {
                ButtonLabel(title: "Выйти из компании…", isLoading: leaving)
            }
            .buttonStyle(LocketButtonStyle(.destructive))
            .confirmationDialog("Выйти из компании?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Выйти из компании", role: .destructive) {
                    Task {
                        leaving = true
                        await model.leaveCircle()
                        leaving = false
                    }
                }
            } message: {
                Text("Твои фото останутся у друзей. Вернуться можно по коду приглашения.")
            }

            Button {
                confirmSignOut = true
            } label: {
                ButtonLabel(title: "Выйти из аккаунта…", isLoading: signingOut)
            }
            .buttonStyle(LocketButtonStyle(.destructive))
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Выйти из аккаунта", role: .destructive) {
                    Task {
                        signingOut = true
                        await model.signOut()
                        signingOut = false
                    }
                }
            } message: {
                Text("Чтобы снова видеть фото друзей, войди по email и паролю.")
            }
        }
        .disabled(leaving || signingOut)
    }

    /// A text action on the right of a section header, one hit target tall.
    private func headerAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)
                .frame(minHeight: Space.hitTarget)
                .contentShape(Rectangle())
        }
    }
}

/// Edits your name or the company's name. A blank value or a server error shows
/// under the field, and the typed value stays.
private struct RenameSheet: View {
    enum Kind { case name, circle }

    let kind: Kind
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @State private var fieldError: String?
    @State private var saving = false
    @FocusState private var focused: Bool

    init(kind: Kind, initialValue: String) {
        self.kind = kind
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                ScreenTitle(title: title, subtitle: subtitle)
                VStack(alignment: .leading, spacing: Space.gap) {
                    FormField(label: label, error: fieldError) {
                        TextField(label, text: $value, prompt: Text(placeholder).foregroundStyle(Palette.faint))
                            .textContentType(contentType)
                            .textInputAutocapitalization(capitalization)
                            .submitLabel(.done)
                            .focused($focused)
                            .onSubmit(save)
                    }
                    Button(action: save) {
                        ButtonLabel(title: "Сохранить", isLoading: saving)
                    }
                    .buttonStyle(LocketButtonStyle(.primary))
                    .disabled(saving)
                    Button("Отменить") { dismiss() }
                        .buttonStyle(LocketButtonStyle(.secondary))
                        .disabled(saving)
                }
            }
            .padding(Space.margin)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.ground)
        .onChange(of: value) { fieldError = nil }
        .interactiveDismissDisabled(saving)
        .presentationDetents([.medium])
        .presentationBackground(Palette.ground)
    }

    private var title: String {
        switch kind {
        case .name: return "Твоё имя"
        case .circle: return "Компания"
        }
    }

    private var subtitle: String {
        switch kind {
        case .name: return "Так тебя видят друзья в ленте и в итогах недели."
        case .circle: return "Новое название увидят все в компании."
        }
    }

    private var label: String {
        switch kind {
        case .name: return "Имя"
        case .circle: return "Название компании"
        }
    }

    private var placeholder: String {
        switch kind {
        case .name: return "Например, Маша"
        case .circle: return "Например, Банда"
        }
    }

    private var blankError: String {
        switch kind {
        case .name: return "Укажи имя — его увидят друзья"
        case .circle: return "Укажи название — его видят все в компании"
        }
    }

    private var contentType: UITextContentType? {
        switch kind {
        case .name: return .givenName
        case .circle: return nil
        }
    }

    private var capitalization: TextInputAutocapitalization {
        switch kind {
        case .name: return .words
        case .circle: return .sentences
        }
    }

    private func save() {
        guard !saving else { return }
        if value.isBlank {
            show(blankError)
            focused = true
            return
        }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                switch kind {
                case .name: try await model.renameMe(value)
                case .circle: try await model.renameCircle(value)
                }
                dismiss()
            } catch is CancellationError {
                // The session lapsed and the app has signed out: nothing to show.
                dismiss()
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    private func show(_ message: String) {
        fieldError = message
        AccessibilityNotification.Announcement(message).post()
    }
}
