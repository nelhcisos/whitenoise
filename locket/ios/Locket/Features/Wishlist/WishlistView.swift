import LinkPresentation
import PhotosUI
import SwiftUI

/// Whose wishlist a sheet shows.
struct WishlistOwner: Identifiable, Hashable {
    let id: String
    let username: String
}

/// A wishlist: what someone would like to get — for a birthday, a holiday or just because.
/// You fill in your own; a friend's opens from the scroll next to their name.
struct WishlistView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let owner: WishlistOwner

    @State private var wishes: [Wish]?
    /// Whose list it is, as the server says (a push may not carry the name).
    @State private var person: Friend?
    @State private var loadFailure: String?
    @State private var actionFailure: String?
    @State private var adding = false
    @State private var wishToDelete: Wish?

    /// The server keeps at most this many.
    static let limit = 50

    private var isMine: Bool { owner.id == model.myId }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.gap) {
                    ScreenTitle(title: isMine ? "Мой виш-лист" : "Виш-лист", subtitle: subtitle)
                    if let loadFailure {
                        InlineError(message: loadFailure) {
                            Task { await load() }
                        }
                    }
                    if let actionFailure {
                        Label(actionFailure, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Palette.negative)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.gap)
                .padding(.bottom, Space.section)
            }
            .background(Palette.ground)
            .refreshable { await load() }
            .task { await load() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .groundBar(for: .navigationBar)
            .sheet(isPresented: $adding) {
                AddWishView { wish in
                    wishes = [wish] + (wishes ?? [])
                }
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: deletePresented,
                titleVisibility: .visible,
                presenting: wishToDelete
            ) { wish in
                Button("Удалить", role: .destructive) {
                    Task { await delete(wish) }
                }
            } message: { _ in
                Text("Друзья больше его не увидят.")
            }
        }
    }

    /// "ёжик · День рождения через 5 дней · 3 желания"; yours says who sees it.
    private var subtitle: String {
        let count = wishes.map { Self.count($0.count) }
        if isMine {
            let who = "друзья видят его рядом с твоим именем"
            return count.map { "\($0) · \(who)" } ?? "Друзья видят его рядом с твоим именем"
        }
        let name = person?.username ?? owner.username
        let parts = [name, Birthday(person?.birthday)?.friendLine, count].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    /// "3 желания", with the number kept next to its word.
    static func count(_ n: Int) -> String {
        "\(n)\(nbsp)\(Russian.plural(n, "желание", "желания", "желаний"))"
    }

    @ViewBuilder
    private var content: some View {
        if let wishes {
            if isMine {
                Button {
                    adding = true
                } label: {
                    Label("Добавить желание", systemImage: "plus")
                }
                .buttonStyle(LocketButtonStyle(.primary))
                .disabled(wishes.count >= Self.limit)
            }
            if wishes.isEmpty {
                EmptyState(text: isMine
                    ? "Добавь, что хочешь получить — на день рождения, праздник или просто так. Ссылкой или названием с картинкой."
                    : "Здесь пока пусто.")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Space.gap) {
                    ForEach(wishes) { wish in
                        WishCard(wish: wish, onDelete: isMine ? { wishToDelete = wish } : nil)
                    }
                }
            }
        } else if loadFailure == nil {
            WishlistSkeleton(columns: columns)
        }
    }

    /// Two tiles side by side; one per row at the largest text sizes.
    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    private func load() async {
        do {
            let response = try await model.wishlist(of: owner.id)
            person = response.user
            wishes = response.wishes
            loadFailure = nil
        } catch is CancellationError {
            // Signed out, or the sheet closed.
        } catch {
            let what = wishes == nil ? "Не удалось загрузить виш-лист." : "Не удалось обновить виш-лист."
            loadFailure = "\(what) \(error.localizedDescription)"
        }
    }

    /// Gone at once; back in its place if the server says no.
    private func delete(_ wish: Wish) async {
        guard let index = wishes?.firstIndex(of: wish) else { return }
        wishes?.remove(at: index)
        actionFailure = nil
        do {
            try await model.deleteWish(id: wish.id)
        } catch is CancellationError {
            // Signed out.
        } catch {
            wishes?.insert(wish, at: min(index, wishes?.count ?? 0))
            actionFailure = "Не удалось удалить: \(error.localizedDescription)"
        }
    }

    private var deleteTitle: String {
        guard let wish = wishToDelete else { return "Удалить желание?" }
        return "Удалить «\(wish.title)»?"
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { wishToDelete != nil },
            set: { isPresented in
                if !isPresented { wishToDelete = nil }
            }
        )
    }
}

// MARK: - A wish

/// A wish as a tile: the picture (or a quiet placeholder), the title, and the site the
/// link goes to. A tile with a link opens it; your own tiles have a menu to delete.
private struct WishCard: View {
    let wish: Wish
    let onDelete: (() -> Void)?
    @Environment(\.openURL) private var openURL

    var body: some View {
        tile
            .overlay(alignment: .topTrailing) {
                if let onDelete { menu(onDelete) }
            }
    }

    @ViewBuilder
    private var tile: some View {
        if let url = wish.url {
            Button {
                openURL(url)
            } label: {
                details
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(wish.title)
            .accessibilityValue(wish.site ?? "")
            .accessibilityHint("Откроет ссылку")
        } else {
            details
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(wish.title)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Palette.surface
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let imageUrl = wish.imageUrl {
                        RemoteImage(url: imageUrl)
                    } else {
                        Image(systemName: wish.url == nil ? "gift" : "link")
                            .font(.title2)
                            .foregroundStyle(Palette.faint)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(wish.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let site = wish.site {
                    Label(site, systemImage: "arrow.up.right")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func menu(_ onDelete: @escaping () -> Void) -> some View {
        Menu {
            Button("Удалить…", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.text)
                .frame(width: 30, height: 30)
                .background(Palette.scrim, in: Circle())
                .frame(width: Space.hitTarget, height: Space.hitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Ещё: \(wish.title)")
        .padding(2)
    }
}

/// The grid's shape while the list loads.
private struct WishlistSkeleton: View {
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Space.gap) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            GeometryReader { geometry in
                                SkeletonBlock(height: geometry.size.height, cornerRadius: Radius.card)
                            }
                        }
                    SkeletonBlock(width: 110, height: 14)
                    SkeletonBlock(width: 70, height: 12)
                }
            }
        }
        .appearsAfter()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Загружаю виш-лист…")
    }
}

// MARK: - Adding a wish

/// A new wish: a link (its title and picture fill in by themselves), a title with a
/// picture from the gallery, or both. A title or a link is enough.
private struct AddWishView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onAdded: (Wish) -> Void

    @State private var link = ""
    @State private var title = ""
    /// The title the link suggested; replaced by the next link only while left as is.
    @State private var suggestedTitle: String?
    @State private var picture: UIImage?
    @State private var pictureFromLink = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var lookup: Lookup = .idle
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var focus: Field?

    private enum Field { case link, title }
    private enum Lookup { case idle, looking, found, nothing }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.gap) {
                    ScreenTitle(title: "Новое желание", subtitle: "Ссылка или название с картинкой — как удобнее")
                    linkField
                    FormField(label: "Что хочешь") {
                        TextField("Что хочешь", text: $title, prompt: Text("Например, плёночный фотоаппарат").foregroundStyle(Palette.faint))
                            .focused($focus, equals: .title)
                            .submitLabel(.done)
                    }
                    pictureField
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Palette.negative)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        Task { await save() }
                    } label: {
                        ButtonLabel(title: saving ? "Сохраняю…" : "Добавить", isLoading: saving)
                    }
                    .buttonStyle(LocketButtonStyle(.primary))
                    .disabled(!canSave || saving)
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.gap)
                .padding(.bottom, Space.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.ground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .groundBar(for: .navigationBar)
            .interactiveDismissDisabled(saving)
            .task(id: link) { await lookUp() }
            .onChange(of: pickerItem) { _, item in
                Task { await loadPicked(item) }
            }
        }
    }

    private var linkField: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormField(label: "Ссылка") {
                HStack(spacing: 8) {
                    TextField("Ссылка", text: $link, prompt: Text("https://…").foregroundStyle(Palette.faint))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .link)
                        .submitLabel(.next)
                        .onSubmit { focus = .title }
                    if link.isEmpty {
                        // The system paste button: no "allow paste?" prompt.
                        PasteButton(payloadType: String.self) { strings in
                            guard let text = strings.first else { return }
                            Task { @MainActor in link = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                        }
                        .labelStyle(.titleOnly)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    } else {
                        Button {
                            link = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Palette.faint)
                                .frame(width: Space.hitTarget, height: Space.hitTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Стереть ссылку")
                    }
                }
            }
            Text(lookupNote)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lookupNote: String {
        switch lookup {
        case .idle: return "Название и картинка подтянутся по ссылке сами."
        case .looking: return "Ищу название и картинку…"
        case .found: return "Готово — поправь, если нужно."
        case .nothing: return "По ссылке ничего не нашлось — напиши название сам."
        }
    }

    private var pictureField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Картинка")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            if let picture {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityLabel("Картинка желания")
                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Text("Другая")
                    }
                    .buttonStyle(LocketButtonStyle(.secondary, fullWidth: false))
                    Button("Убрать") {
                        self.picture = nil
                        pictureFromLink = false
                        pickerItem = nil
                    }
                    .buttonStyle(LocketButtonStyle(.secondary, fullWidth: false))
                }
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Выбрать из галереи", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(LocketButtonStyle(.secondary))
            }
        }
    }

    private var canSave: Bool { !title.isBlank || !link.isBlank }

    /// After a short pause in typing, asks the page for its title and picture.
    private func lookUp() async {
        guard let url = Self.webURL(link) else {
            lookup = .idle
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(600))
        } catch {
            return // the link changed again
        }
        lookup = .looking
        let found = await LinkPreview.fetch(url)
        guard !Task.isCancelled else { return }
        guard let found, found.title != nil || found.image != nil else {
            lookup = .nothing
            return
        }
        if let suggestion = found.title, title.isBlank || title == suggestedTitle {
            title = suggestion
            suggestedTitle = suggestion
        }
        if let image = found.image, picture == nil || pictureFromLink {
            picture = image
            pictureFromLink = true
        }
        lookup = .found
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            failure = "Не получилось открыть фото из галереи. Попробуй выбрать другое."
            pickerItem = nil
            return
        }
        failure = nil
        picture = image.squareCropped(side: 1080)
        pictureFromLink = false
    }

    private func save() async {
        let typed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty && Self.webURL(typed) == nil {
            failure = "Это не похоже на ссылку на сайт. Проверь адрес или сотри его."
            return
        }
        saving = true
        failure = nil
        defer { saving = false }
        let jpeg = picture?.squareCropped(side: 1080).jpegData(compressionQuality: 0.82)
        do {
            let wish = try await model.addWish(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines), url: typed, jpeg: jpeg
            )
            onAdded(wish)
            dismiss()
        } catch is CancellationError {
            // Signed out.
        } catch {
            failure = "Не сохранилось: \(error.localizedDescription)"
        }
    }

    /// A web address as the server takes it: http or https, a real host, nothing before "@".
    /// "ozon.ru/item" gets https:// in front.
    static func webURL(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(" ") else { return nil }
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), host.contains("."),
              url.user() == nil, url.password() == nil
        else { return nil }
        return url
    }
}

/// The page's own title and picture, fetched on the phone with LinkPresentation —
/// the server never opens the links people paste.
enum LinkPreview {
    struct Found {
        let title: String?
        let image: UIImage?
    }

    @MainActor
    static func fetch(_ url: URL) async -> Found? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return nil }
        let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        var image: UIImage?
        if let item = metadata.imageProvider {
            image = await loadImage(item)
        }
        return Found(title: title?.isEmpty == false ? title : nil, image: image)
    }

    /// The picture travels as JPEG data, which is safe to hand from the loader's thread.
    private static func loadImage(_ item: NSItemProvider) async -> UIImage? {
        let data: Data? = await withCheckedContinuation { continuation in
            item.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: (object as? UIImage)?.jpegData(compressionQuality: 0.9))
            }
        }
        return data.flatMap { UIImage(data: $0) }
    }
}
