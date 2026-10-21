import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            switch model.phase {
            case .launching:
                LaunchView()
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

/// While the session loads: the wordmark the launch screen hands off to, no spinner.
/// A slow server gets one honest line after a second.
private struct LaunchView: View {
    var body: some View {
        VStack(spacing: 12) {
            Wordmark()
            Text("Подключаюсь к серверу…")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .appearsAfter(.seconds(1))
        }
        .accessibilityElement(children: .combine)
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
                    // Padding sits on the text, so a wrapped error keeps air above and below
                    // while its first line still lines up with the 44 pt close button.
                    Text(toast.text)
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
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
                .groundBar(for: .tabBar)
                .tabItem { Label("Камера", systemImage: "camera") }
                .tag(AppModel.Tab.camera)
            FeedView()
                .groundBar(for: .tabBar)
                .tabItem { Label("Лента", systemImage: "photo.stack") }
                .tag(AppModel.Tab.feed)
                // The feed's own title already says how many wait, so the badge
                // only shows from the other tabs.
                .badge(model.selectedTab == .feed ? 0 : model.unratedCount)
            WeekView()
                .groundBar(for: .tabBar)
                .tabItem { Label("Неделя", systemImage: "trophy") }
                .tag(AppModel.Tab.week)
            FriendsView()
                .groundBar(for: .tabBar)
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

extension View {
    /// An opaque ground-coloured bar: no system blur material under scrolled content.
    func groundBar(for bar: ToolbarPlacement) -> some View {
        toolbarBackground(Palette.ground, for: bar)
            .toolbarBackground(.visible, for: bar)
    }
}
