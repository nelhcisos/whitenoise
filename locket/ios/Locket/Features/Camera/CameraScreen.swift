import AVFoundation
import PhotosUI
import SwiftUI

/// The first tab: take or pick a square photo, add a caption, send it to the circle.
/// The viewfinder is the largest thing on screen; "Send" is its one accent control.
struct CameraScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var camera = CameraModel()
    @State private var captured: UIImage?
    @State private var caption = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var sending = false
    @State private var sendError: String?
    @FocusState private var captionFocused: Bool

    private let captionLimit = 60
    private let sideControl: CGFloat = 60
    private let mainControl: CGFloat = 84

    var body: some View {
        VStack(spacing: Space.gap) {
            header
            viewfinder
            controls
                .padding(.top, Space.gap)
            if let sendError {
                sendFailure(sendError)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.gap)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            Task { await loadPicked(item) }
        }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(alignment: .center, spacing: Space.gap) {
            ScreenTitle(title: model.circle?.name ?? "Locket", subtitle: audience)
            if !friends.isEmpty {
                HStack(spacing: -10) {
                    ForEach(friends.prefix(4)) { friend in
                        Avatar(name: friend.name, size: 32)
                            .padding(2)
                            .background(Palette.ground, in: Circle())
                    }
                }
                .fixedSize()
                .accessibilityHidden(true)
            }
        }
    }

    private var friends: [Member] {
        model.members.filter { $0.id != model.myId }
    }

    private var audience: String {
        let count = friends.count
        guard count > 0 else { return "Друзей пока нет — позови их во вкладке «Друзья»" }
        return "Увидят: \(count)\(nbsp)\(Russian.plural(count, "друг", "друга", "друзей"))"
    }

    private var viewfinder: some View {
        Palette.surface
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let captured {
                    Image(uiImage: captured)
                        .resizable()
                        .scaledToFill()
                        .accessibilityLabel("Фото для отправки")
                } else {
                    switch camera.status {
                    case .ready, .unknown:
                        CameraPreview(session: camera.session)
                    case .denied:
                        cameraMessage("Разреши доступ к камере в Настройках или выбери фото из галереи.", opensSettings: true)
                    case .unavailable:
                        cameraMessage("Камера недоступна — выбери фото из галереи.", opensSettings: false)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if captured != nil { captionField }
            }
            .overlay(alignment: .topTrailing) {
                flashToggle
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
    }

    private func cameraMessage(_ text: String, opensSettings: Bool) -> some View {
        VStack(spacing: Space.gap) {
            Text(text)
                .font(.body)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if opensSettings {
                Button("Открыть настройки") { openSettings() }
                    .buttonStyle(LocketButtonStyle(.secondary, fullWidth: false))
            }
        }
        .padding(Space.cardPadding)
    }

    @ViewBuilder
    private var flashToggle: some View {
        if captured == nil && camera.status == .ready {
            Button {
                camera.flashOn.toggle()
            } label: {
                Image(systemName: camera.flashOn ? "bolt.fill" : "bolt.slash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(camera.flashOn ? Palette.accent : Palette.text)
                    .frame(width: Space.hitTarget, height: Space.hitTarget)
                    .background(Palette.ground.opacity(0.55), in: Circle())
            }
            .buttonStyle(RoundControlStyle())
            .accessibilityLabel("Вспышка")
            .accessibilityValue(camera.flashOn ? "включена" : "выключена")
            .padding(12)
        }
    }

    private var captionField: some View {
        TextField("Подпись", text: $caption, prompt: Text("Подпись…").foregroundStyle(Palette.muted))
            .focused($captionFocused)
            .submitLabel(.done)
            .multilineTextAlignment(.center)
            .font(.body.weight(.semibold))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, Space.gap)
            .frame(minHeight: Space.hitTarget)
            .background(Palette.ground.opacity(0.55), in: Capsule())
            .padding(Space.gap)
            .disabled(sending)
            .onChange(of: caption) { _, value in
                if value.count > captionLimit { caption = String(value.prefix(captionLimit)) }
            }
    }

    @ViewBuilder
    private var controls: some View {
        if let captured {
            HStack(spacing: 0) {
                roundButton("xmark", label: "Отменить") { discard() }
                    .disabled(sending)
                    .frame(maxWidth: .infinity)
                sendButton(captured)
                Color.clear
                    .frame(width: sideControl, height: sideControl)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        } else {
            HStack(spacing: 0) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    roundIcon("photo.on.rectangle")
                }
                .buttonStyle(RoundControlStyle())
                .accessibilityLabel("Выбрать из галереи")
                .frame(maxWidth: .infinity)
                shutter
                roundButton("arrow.triangle.2.circlepath", label: "Сменить камеру") { camera.flip() }
                    .disabled(camera.status != .ready)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var shutter: some View {
        Button {
            shoot()
        } label: {
            Circle()
                .strokeBorder(Palette.text, lineWidth: 5)
                .overlay(Circle().fill(Palette.text).padding(10))
                .frame(width: mainControl, height: mainControl)
        }
        .buttonStyle(RoundControlStyle())
        .disabled(camera.status != .ready || camera.isCapturing)
        .accessibilityLabel("Сделать фото")
    }

    private func sendButton(_ image: UIImage) -> some View {
        Button {
            Task { await send(image) }
        } label: {
            ZStack {
                Circle().fill(Palette.accent)
                if sending {
                    ProgressView()
                        .tint(Palette.onFill)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Palette.onFill)
                }
            }
            .frame(width: mainControl, height: mainControl)
        }
        .buttonStyle(RoundControlStyle(dimsWhenDisabled: false))
        .disabled(sending)
        .accessibilityLabel("Отправить друзьям")
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { roundIcon(icon) }
            .buttonStyle(RoundControlStyle())
            .accessibilityLabel(label)
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Palette.text)
            .frame(width: sideControl, height: sideControl)
            .background(Palette.surface, in: Circle())
    }

    private func sendFailure(_ message: String) -> some View {
        Label(failureText(message), systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(Palette.negative)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failureText(_ message: String) -> String {
        "Не отправилось: \(message) Фото на месте — нажми «Отправить» ещё раз."
    }

    // MARK: - Actions

    private var motion: Animation? { reduceMotion ? nil : .snappy }

    private func shoot() {
        camera.capture { image in
            guard let image else {
                model.show(error: "Не получилось сделать фото. Попробуй ещё раз.")
                return
            }
            withAnimation(motion) { captured = image }
        }
    }

    private func send(_ image: UIImage) async {
        guard !sending else { return }
        sending = true
        sendError = nil
        captionFocused = false
        defer { sending = false }
        do {
            try await model.upload(image, caption: caption.trimmingCharacters(in: .whitespacesAndNewlines))
            discard()
        } catch is CancellationError {
        } catch {
            let message = sentence(error.localizedDescription)
            withAnimation(motion) { sendError = message }
            AccessibilityNotification.Announcement(failureText(message)).post()
        }
    }

    private func discard() {
        withAnimation(motion) { captured = nil }
        caption = ""
        captionFocused = false
        pickerItem = nil
        sendError = nil
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            model.show(error: "Не получилось открыть фото из галереи. Попробуй выбрать другое.")
            pickerItem = nil
            return
        }
        withAnimation(motion) { captured = image.squareCropped(side: 1080) }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    /// Ends the message with a full stop so the hint after it reads as its own sentence.
    private func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !".!?…".contains(last) else { return trimmed }
        return trimmed + "."
    }
}

/// Round camera controls: dim while pressed and, unless told otherwise, while unavailable.
private struct RoundControlStyle: ButtonStyle {
    var dimsWhenDisabled = true

    func makeBody(configuration: Configuration) -> some View {
        RoundControl(configuration: configuration, dimsWhenDisabled: dimsWhenDisabled)
    }

    private struct RoundControl: View {
        let configuration: ButtonStyleConfiguration
        let dimsWhenDisabled: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .opacity(opacity)
                .contentShape(Circle())
        }

        private var opacity: Double {
            if !isEnabled && dimsWhenDisabled { return 0.4 }
            return configuration.isPressed ? 0.7 : 1
        }
    }
}

/// The live capture session, filling its frame like the square photo it will become.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
