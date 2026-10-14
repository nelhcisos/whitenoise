import SwiftUI
import UserNotifications

struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var editingName = false
    @State private var newName = ""
    @State private var editingCircle = false
    @State private var newCircleName = ""
    @State private var confirmLeave = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if let circle = model.circle {
                    circleSection(circle)
                    Section("В компании · \(model.members.count)") {
                        ForEach(model.members) { member in
                            HStack(spacing: 12) {
                                Avatar(name: member.name, size: 32)
                                Text(member.id == model.myId ? "\(member.name) (ты)" : member.name)
                                Spacer()
                                if member.id == circle.ownerId {
                                    Text("создатель").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                notificationsSection

                Section("Профиль") {
                    HStack {
                        Text(model.me?.user.name ?? "")
                        Spacer()
                        Button("Изменить") {
                            newName = model.me?.user.name ?? ""
                            editingName = true
                        }
                        .buttonStyle(.borderless)
                    }
                    if let email = model.me?.user.email {
                        Text(email).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Выйти из компании", role: .destructive) { confirmLeave = true }
                    Button("Выйти из аккаунта", role: .destructive) { confirmSignOut = true }
                }
            }
            .navigationTitle("Друзья")
            .task { notificationStatus = await PushRegistrar.authorizationStatus() }
            .alert("Твоё имя", isPresented: $editingName) {
                TextField("Имя", text: $newName)
                Button("Сохранить") { Task { await model.renameMe(newName) } }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Название компании", isPresented: $editingCircle) {
                TextField("Название", text: $newCircleName)
                Button("Сохранить") { Task { await model.renameCircle(newCircleName) } }
                Button("Отмена", role: .cancel) {}
            }
            .confirmationDialog("Выйти из компании?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { Task { await model.leaveCircle() } }
            } message: {
                Text("Твои фото останутся у друзей. Вернуться можно по коду приглашения.")
            }
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { Task { await model.signOut() } }
            }
        }
    }

    private func circleSection(_ circle: FriendCircle) -> some View {
        Section {
            HStack {
                Text(circle.name).font(.title2.bold())
                Spacer()
                Button("Изменить") {
                    newCircleName = circle.name
                    editingCircle = true
                }
                .buttonStyle(.borderless)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Код приглашения").font(.caption).foregroundStyle(.secondary)
                Text(circle.inviteCode)
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .kerning(4)
                    .textSelection(.enabled)
                HStack {
                    Button {
                        UIPasteboard.general.string = circle.inviteCode
                        model.show(toast: "Код скопирован")
                    } label: {
                        Label("Скопировать", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    ShareLink(item: "Залетай к нам в Locket «\(circle.name)» 📸 Код компании: \(circle.inviteCode)") {
                        Label("Позвать друзей", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(.black)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var notificationsSection: some View {
        Section {
            switch notificationStatus {
            case .denied:
                Label("Уведомления выключены", systemImage: "bell.slash")
                Button("Включить в Настройках") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            case .notDetermined:
                Button("Включить уведомления") {
                    Task {
                        await PushRegistrar.requestPermissionAndRegister()
                        notificationStatus = await PushRegistrar.authorizationStatus()
                    }
                }
            default:
                Label("Уведомления включены", systemImage: "bell.badge.fill")
            }
        } header: {
            Text("Уведомления")
        } footer: {
            Text("Когда друг выложит фото, удерживай уведомление на экране блокировки — появятся кнопки 🔥 Огонь, 🎨 Креативно и 😂 Смешно. Оценка уходит сразу, приложение открывать не нужно.\n\nДобавь виджет Locket на экран «Домой»: там всегда последнее фото друзей и те же кнопки.")
        }
    }
}
