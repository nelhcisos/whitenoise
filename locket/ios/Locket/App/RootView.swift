import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            switch model.phase {
            case .launching:
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.faint)
                    .appearsAfter()
            case .offline(let message):
                OfflineView(message: message)
            case .signedOut:
                AuthView()
            case .needsCircle:
                CircleSetupView()
            case .ready:
                MainTabView()
            }
        }
        .overlay(alignment: .top) { ToastView() }
        .task { await model.start() }
    }
}

/// No connection at launch: what happened, how to get out of it.
private struct OfflineView: View {
    @Environment(AppModel.self) private var model
    @State private var retrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            ScreenTitle(title: "Нет связи с Locket", subtitle: message)
            Button {
                Task {
                    retrying = true
                    await model.retry()
                    retrying = false
                }
            } label: {
                ButtonLabel(title: "Повторить", isLoading: retrying)
            }
            .buttonStyle(LocketButtonStyle(.primary))
            .disabled(retrying)
        }
        .padding(Space.margin)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    let message: String
}

/// The app's one place for short messages; errors stay longer and carry a close button.
private struct ToastView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let toast = model.toast {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if toast.isError {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Palette.negative)
                            .accessibilityHidden(true)
                    }
                    Text(toast.text)
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if toast.isError {
                        Spacer(minLength: 8)
                        Button {
                            model.dismissToast()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.muted)
                                .frame(width: Space.hitTarget, height: Space.hitTarget)
                        }
                        .accessibilityLabel("Закрыть")
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, toast.isError ? 0 : 16)
                .padding(.vertical, toast.isError ? 0 : 12)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .padding(.horizontal, Space.margin)
                .padding(.top, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: model.toast)
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            CameraScreen()
                .tabItem { Label("Камера", systemImage: "camera") }
                .tag(AppModel.Tab.camera)
            FeedView()
                .tabItem { Label("Лента", systemImage: "photo.stack") }
                .tag(AppModel.Tab.feed)
                .badge(model.unratedCount)
            WeekView()
                .tabItem { Label("Неделя", systemImage: "trophy") }
                .tag(AppModel.Tab.week)
            FriendsView()
                .tabItem { Label("Друзья", systemImage: "person.2") }
                .tag(AppModel.Tab.friends)
        }
        .task { await model.refreshAll() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await model.refreshAll() } }
        }
        .sheet(item: $model.presentedWeek) { week in
            NavigationStack {
                WeekResultsView(results: week)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Закрыть") { model.presentedWeek = nil }
                        }
                    }
            }
        }
    }
}
