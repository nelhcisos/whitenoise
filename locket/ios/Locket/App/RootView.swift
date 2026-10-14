import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.phase {
            case .launching:
                ProgressView().controlSize(.large)
            case .offline(let message):
                ContentUnavailableView {
                    Label("Нет связи", systemImage: "wifi.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Повторить") { Task { await model.retry() } }
                        .buttonStyle(.borderedProminent)
                }
            case .signedOut:
                AuthView()
            case .needsCircle:
                CircleSetupView()
            case .ready:
                MainTabView()
            }
        }
        .animation(.default, value: model.phase)
        .task { await model.start() }
        .alert("Упс", isPresented: alertBinding, presenting: model.alert) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            CameraScreen()
                .tabItem { Label("Камера", systemImage: "camera.fill") }
                .tag(AppModel.Tab.camera)
            FeedView()
                .tabItem { Label("Лента", systemImage: "photo.stack.fill") }
                .tag(AppModel.Tab.feed)
            WeekView()
                .tabItem { Label("Неделя", systemImage: "trophy.fill") }
                .tag(AppModel.Tab.week)
            FriendsView()
                .tabItem { Label("Друзья", systemImage: "person.2.fill") }
                .tag(AppModel.Tab.friends)
        }
        .task { await model.refreshAll() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await model.refreshAll() } }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring, value: model.toast)
        .sheet(item: $model.presentedWeek) { week in
            NavigationStack {
                WeekResultsView(results: week)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Готово") { model.presentedWeek = nil }
                        }
                    }
            }
        }
    }
}
