import SwiftUI

/// Browser demo only: a push the server would send, drawn inside the app like an iOS
/// banner, so the demo needs no notification permission.
struct DemoBanner: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let push: PushInfo
}

enum DemoPush {
    /// барсук's password in the demo data.
    static let password = "1234"

    /// Today's birthday in the demo; tapping the banner opens their wishlist.
    static var birthday: DemoBanner {
        let name = DemoBackend.birthdayName
        return DemoBanner(
            title: "Сегодня день рождения 🎂",
            body: "\(name) празднует — поздравь! Виш-лист — по нажатию",
            push: PushInfo(type: "birthday", userId: DemoBackend.birthdayUserId, username: name)
        )
    }
}

/// The banner at the top of the screen: tap opens the push, a swipe up hides it.
struct DemoBannerView: View {
    let banner: DemoBanner
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.accent)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "birthday.cake.fill")
                            .font(.body)
                            .foregroundStyle(Palette.onFill)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(banner.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 8)
                        Text("сейчас")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                    Text(banner.body)
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -20 { close() }
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Уведомление: \(banner.title). \(banner.body)")
        .accessibilityHint("Откроет виш-лист")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Закрыть", close)
    }
}
