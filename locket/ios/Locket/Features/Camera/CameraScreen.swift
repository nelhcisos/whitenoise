import AVFoundation
import PhotosUI
import SwiftUI

struct CameraScreen: View {
    @Environment(AppModel.self) private var model
    @State private var camera = CameraModel()
    @State private var captured: UIImage?
    @State private var caption = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var sending = false
    @FocusState private var captionFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            header
            viewfinder
            controls
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            Task { await loadPicked(item) }
        }
    }

    // MARK: - Parts

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.circle?.name ?? "Locket").font(.title2.bold())
                Text("Фото увидят: \(max(model.members.count - 1, 0))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: -10) {
                ForEach(model.members.prefix(5)) { member in
                    Avatar(name: member.name, size: 34)
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                }
            }
        }
    }

    private var viewfinder: some View {
        Color.card
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let captured {
                    Image(uiImage: captured).resizable().scaledToFill()
                } else {
                    switch camera.status {
                    case .ready, .unknown:
                        CameraPreview(session: camera.session)
                    case .denied:
                        cameraMessage("Разреши доступ к камере в Настройках", icon: "camera.badge.ellipsis", showSettings: true)
                    case .unavailable:
                        cameraMessage("Камера недоступна — выбери фото из галереи", icon: "camera", showSettings: false)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if captured != nil { captionField }
            }
            .overlay(alignment: .topTrailing) {
                if captured == nil && camera.status == .ready {
                    Button {
                        camera.flashOn.toggle()
                    } label: {
                        Image(systemName: camera.flashOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.headline)
                            .foregroundStyle(camera.flashOn ? Color.locketYellow : .white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.4), in: Circle())
                    }
                    .padding(14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
    }

    private var captionField: some View {
        TextField("Добавь подпись…", text: $caption)
            .focused($captionFocused)
            .submitLabel(.done)
            .multilineTextAlignment(.center)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.45), in: Capsule())
            .padding(16)
            .onChange(of: caption) { _, value in
                if value.count > 60 { caption = String(value.prefix(60)) }
            }
    }

    @ViewBuilder
    private var controls: some View {
        if let captured {
            HStack(spacing: 44) {
                roundButton(icon: "xmark") { discard() }
                Button {
                    Task { await send(captured) }
                } label: {
                    ZStack {
                        Circle().fill(Color.locketYellow).frame(width: 84, height: 84)
                        if sending {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                }
                .disabled(sending)
                Color.clear.frame(width: 60, height: 60)
            }
        } else {
            HStack(spacing: 44) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    roundIcon("photo.on.rectangle")
                }
                Button {
                    shoot()
                } label: {
                    Circle()
                        .strokeBorder(Color.locketYellow, lineWidth: 5)
                        .frame(width: 84, height: 84)
                        .overlay(Circle().fill(Color.white).padding(10))
                }
                .disabled(camera.status != .ready || camera.isCapturing)
                roundButton(icon: "arrow.triangle.2.circlepath") { camera.flip() }
                    .disabled(camera.status != .ready)
            }
        }
    }

    private func roundButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { roundIcon(icon) }
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 60, height: 60)
            .background(Color.card, in: Circle())
    }

    private func cameraMessage(_ text: String, icon: String, showSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Открыть настройки", destination: url).font(.headline)
            }
        }
        .padding(32)
    }

    // MARK: - Actions

    private func shoot() {
        camera.capture { image in
            guard let image else { return }
            withAnimation(.snappy) { captured = image }
        }
    }

    private func send(_ image: UIImage) async {
        sending = true
        defer { sending = false }
        do {
            try await model.upload(image, caption: caption.trimmingCharacters(in: .whitespacesAndNewlines))
            discard()
        } catch is CancellationError {
        } catch {
            model.alert = error.localizedDescription
        }
    }

    private func discard() {
        withAnimation(.snappy) { captured = nil }
        caption = ""
        captionFocused = false
        pickerItem = nil
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        withAnimation(.snappy) { captured = image.squareCropped(side: 1080) }
    }
}

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
