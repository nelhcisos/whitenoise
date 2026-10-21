import SwiftUI
import UserNotifications

/// The circle: how to invite friends (the code is the largest thing on screen), who is in it,
/// notifications, your profile and, last, the ways out.
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var editingName = false
    @State private var newName = ""
    @State private var editingCircle = false
    @State private var newCircleName = ""
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
        .alert("Твоё имя", isPresented: $editingName) {
            TextField("Например, Маша", text: $newName)
            Button("Сохранить") { Task { await model.renameMe(newName) } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Так тебя видят друзья в ленте и в итогах недели.")
        }
        .alert("Название компании", isPresented: $editingCircle) {
            TextField("Например, Банда", text: $newCircleName)
            Button("Сохранить") { Task { await model.renameCircle(newCircleName) } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Новое название увидят все в компании.")
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
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Компания") {
                headerAction("Изменить название…") {
                    newCircleName = circle.name
                    editingCircle = true
                }
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
        VStack(alignment: .leading, spacing: 8) {
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
            Avatar(name: member.name, size: 32)
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
        VStack(alignment: .leading, spacing: 8) {
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
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Профиль") {
                headerAction("Изменить имя…") {
                    newName = model.me?.user.name ?? ""
                    editingName = true
                }
            }
            Card {
                HStack(spacing: 12) {
                    Avatar(name: model.me?.user.name ?? "", size: 40)
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
