import DesignSystem
import Env
import Models
import NetworkClient
import NukeUI
import PhotosUI
import StatusKit
import SwiftUI

@MainActor
public struct EditAccountView: View {
  private enum ViewState {
    case loading
    case loaded
    case error
  }

  private struct FieldEdit: Identifiable {
    let id = UUID()
    var name: String
    var value: String
  }

  private enum ImageKind {
    case avatar
    case header

    var filename: String {
      switch self {
      case .avatar: "avatar"
      case .header: "header"
      }
    }

    var deleteEndpoint: any Endpoint {
      switch self {
      case .avatar: Profile.deleteAvatar
      case .header: Profile.deleteHeader
      }
    }

    var maxHeight: CGFloat {
      switch self {
      case .avatar: 400
      case .header: 500
      }
    }

    var maxWidth: CGFloat {
      switch self {
      case .avatar: 400
      case .header: 1500
      }
    }
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(MastodonClient.self) private var client
  @Environment(Theme.self) private var theme
  @Environment(UserPreferences.self) private var userPrefs

  @State private var viewState: ViewState = .loading

  @State private var displayName: String = ""
  @State private var note: String = ""
  @State private var postPrivacy = Models.Visibility.pub
  @State private var isSensitive: Bool = false
  @State private var isBot: Bool = false
  @State private var isLocked: Bool = false
  @State private var isDiscoverable: Bool = false
  @State private var fields: [FieldEdit] = []
  @State private var avatar: URL?
  @State private var header: URL?

  @State private var isPhotoPickerPresented: Bool = false
  @State private var changingImage: ImageKind?
  @State private var mediaPickers: [PhotosPickerItem] = []

  @State private var isSaving: Bool = false
  @State private var saveError: Bool = false

  public init() {}

  public var body: some View {
    NavigationStack {
      Form {
        switch viewState {
        case .loading:
          loadingSection
        case .error:
          errorSection
        case .loaded:
          imagesSection
          aboutSection
          fieldsSection
          postSettingsSection
          accountSection
        }
      }
      .environment(\.editMode, .constant(.active))
      #if !os(visionOS)
        .scrollContentBackground(.hidden)
        .background(theme.secondaryBackgroundColor)
        .scrollDismissesKeyboard(.immediately)
      #endif
      .navigationTitle("account.edit.navigation-title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        toolbarContent
      }
      .alert(
        "account.edit.error.save.title",
        isPresented: $saveError,
        actions: {
          Button("alert.button.ok", action: {})
        }, message: { Text("account.edit.error.save.message") }
      )
      .onChange(of: isPhotoPickerPresented) { _, isPresented in
        if !isPresented, mediaPickers.isEmpty {
          changingImage = nil
        }
      }
      .onChange(of: mediaPickers) { _, pickers in
        guard let item = pickers.first else { return }
        Task { await handlePickedItem(item) }
      }
      .task {
        await fetchAccount()
      }
    }
  }

  private var loadingSection: some View {
    Section {
      HStack {
        Spacer()
        ProgressView()
        Spacer()
      }
    }
    #if !os(visionOS)
      .listRowBackground(theme.primaryBackgroundColor)
    #endif
  }

  private var errorSection: some View {
    Section {
      VStack(spacing: 8) {
        Text("status.error.title")
        Button("action.retry") {
          viewState = .loading
          Task { await fetchAccount() }
        }
      }
      .frame(maxWidth: .infinity)
    }
    #if !os(visionOS)
      .listRowBackground(theme.primaryBackgroundColor)
    #endif
  }

  private var imagesSection: some View {
    Section {
      ZStack(alignment: .center) {
        if let header {
          ZStack(alignment: .topLeading) {
            LazyImage(url: header) { state in
              if let image = state.image {
                image
                  .resizable()
                  .aspectRatio(contentMode: .fill)
                  .frame(height: 150)
                  .clipShape(RoundedRectangle(cornerRadius: 8))
                  .clipped()
              } else {
                RoundedRectangle(cornerRadius: 8)
                  .foregroundStyle(theme.primaryBackgroundColor)
                  .frame(height: 150)
              }
            }
            .frame(height: 150)
          }
        }
        ZStack(alignment: .bottomLeading) {
          AvatarView(avatar, config: .account)
          Menu {
            Button("account.edit.avatar") {
              changingImage = .avatar
              isPhotoPickerPresented = true
            }
            Button("account.edit.header") {
              changingImage = .header
              isPhotoPickerPresented = true
            }
            if avatar != nil || header != nil {
              Divider()
            }
            if avatar != nil {
              Button("account.edit.avatar.delete", role: .destructive) {
                Task {
                  await deleteImage(.avatar)
                }
              }
            }
            if header != nil {
              Button("account.edit.header.delete", role: .destructive) {
                Task {
                  await deleteImage(.header)
                }
              }
            }
          } label: {
            Image(systemName: "photo.badge.plus")
              .foregroundStyle(.white)
          }
          .buttonStyle(.borderedProminent)
          .clipShape(Circle())
          .offset(x: -8, y: 8)
          .padding(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
        }
      }
      .frame(minWidth: 0, maxWidth: .infinity)
      .overlay {
        if changingImage != nil {
          ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 8)
              .foregroundStyle(Color.black.opacity(0.40))
            ProgressView()
          }
        }
      }
      .listRowInsets(EdgeInsets())
    }
    .listRowBackground(theme.secondaryBackgroundColor)
    .photosPicker(
      isPresented: $isPhotoPickerPresented,
      selection: $mediaPickers,
      maxSelectionCount: 1,
      matching: .any(of: [.images]),
      photoLibrary: .shared())
  }

  @ViewBuilder
  private var aboutSection: some View {
    Section("account.edit.display-name") {
      TextField("account.edit.display-name", text: $displayName)
    }
    .listRowBackground(theme.primaryBackgroundColor)
    Section("account.edit.about") {
      TextField("account.edit.about", text: $note, axis: .vertical)
        .frame(maxHeight: 150)
    }
    #if !os(visionOS)
      .listRowBackground(theme.primaryBackgroundColor)
    #endif
  }

  private var postSettingsSection: some View {
    Section("account.edit.post-settings.section-title") {
      if !userPrefs.useInstanceContentSettings {
        Text("account.edit.post-settings.content-settings-reference")
      }
      Picker(selection: $postPrivacy) {
        ForEach(Models.Visibility.supportDefault, id: \.rawValue) { privacy in
          Text(privacy.title).tag(privacy)
        }
      } label: {
        Label("account.edit.post-settings.privacy", systemImage: "lock")
      }
      .pickerStyle(.menu)
      Toggle(isOn: $isSensitive) {
        Label("account.edit.post-settings.sensitive", systemImage: "eye")
      }
    }
    #if !os(visionOS)
      .listRowBackground(theme.primaryBackgroundColor)
    #endif
  }

  private var accountSection: some View {
    Section("account.edit.account-settings.section-title") {
      Toggle(isOn: $isLocked) {
        Label("account.edit.account-settings.private", systemImage: "lock")
      }
      Toggle(isOn: $isBot) {
        Label(
          "account.edit.account-settings.bot",
          systemImage: "laptopcomputer.trianglebadge.exclamationmark")
      }
      Toggle(isOn: $isDiscoverable) {
        Label("account.edit.account-settings.discoverable", systemImage: "magnifyingglass")
      }
    }
    #if !os(visionOS)
      .listRowBackground(theme.primaryBackgroundColor)
    #endif
  }

  private var fieldsSection: some View {
    Section("account.edit.metadata-section-title") {
      ForEach($fields) { $field in
        VStack(alignment: .leading) {
          TextField("account.edit.metadata-name-placeholder", text: $field.name)
            .font(.scaledHeadline)
          TextField("account.edit.metadata-value-placeholder", text: $field.value)
            .emojiText.size(Font.scaledBodyFont.emojiSize)
            .emojiText.baselineOffset(Font.scaledBodyFont.emojiBaselineOffset)
            .foregroundColor(theme.tintColor)
        }
      }
      .onMove(perform: { indexSet, newOffset in
        fields.move(fromOffsets: indexSet, toOffset: newOffset)
      })
      .onDelete { indexes in
        fields.remove(atOffsets: indexes)
      }
      if fields.count < 4 {
        Button {
          withAnimation {
            fields.append(.init(name: "", value: ""))
          }
        } label: {
          Text("account.edit.add-metadata-button")
            .foregroundColor(theme.tintColor)
        }
      }
    }
    #if !os(visionOS)
      .listRowBackground(theme.primaryBackgroundColor)
    #endif
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    CancelToolbarItem()

    ToolbarItem(placement: .navigationBarTrailing) {
      Button {
        Task {
          if await save() {
            dismiss()
          }
        }
      } label: {
        if isSaving {
          ProgressView()
        } else {
          Text("action.save").bold()
        }
      }
      .disabled(viewState != .loaded)
    }
  }

  // MARK: - Actions

  private func fetchAccount() async {
    do {
      let account: Account = try await client.get(endpoint: Accounts.verifyCredentials)
      displayName = account.displayName ?? ""
      note = account.source?.note ?? ""
      postPrivacy = account.source?.privacy ?? .pub
      isSensitive = account.source?.sensitive ?? false
      isBot = account.bot
      isLocked = account.locked
      isDiscoverable = account.discoverable ?? false
      avatar = account.haveAvatar ? account.avatar : nil
      header = account.haveHeader ? account.header : nil
      fields = account.source?.fields.map { .init(name: $0.name, value: $0.value.asRawText) } ?? []
      withAnimation {
        viewState = .loaded
      }
    } catch {
      viewState = .error
    }
  }

  private func refreshImages() async {
    guard let account: Account = try? await client.get(endpoint: Accounts.verifyCredentials) else {
      return
    }
    avatar = account.haveAvatar ? account.avatar : nil
    header = account.haveHeader ? account.header : nil
  }

  private func save() async -> Bool {
    guard viewState == .loaded, !isSaving else { return false }
    isSaving = true
    defer { isSaving = false }
    do {
      let data = UpdateCredentialsData(
        displayName: displayName,
        note: note,
        source: .init(privacy: postPrivacy, sensitive: isSensitive),
        bot: isBot,
        locked: isLocked,
        discoverable: isDiscoverable,
        fieldsAttributes: fields.map { .init(name: $0.name, value: $0.value) })
      let response = try await client.patch(endpoint: Accounts.updateCredentials(json: data))
      guard response?.statusCode == 200 else {
        saveError = true
        return false
      }
      return true
    } catch {
      saveError = true
      return false
    }
  }

  private func deleteImage(_ kind: ImageKind) async {
    do {
      let response = try await client.delete(endpoint: kind.deleteEndpoint)
      guard response?.statusCode == 200 else {
        saveError = true
        return
      }
      switch kind {
      case .avatar: avatar = nil
      case .header: header = nil
      }
    } catch {
      saveError = true
    }
  }

  private func handlePickedItem(_ item: PhotosPickerItem) async {
    defer {
      changingImage = nil
      mediaPickers = []
    }
    guard let kind = changingImage else { return }
    guard let data = await imageData(for: item, kind: kind),
      await uploadImage(data: data, kind: kind)
    else {
      saveError = true
      return
    }
    await refreshImages()
  }

  private func uploadImage(data: Data, kind: ImageKind) async -> Bool {
    do {
      let response = try await client.mediaUpload(
        endpoint: Accounts.updateCredentialsMedia,
        version: .v1,
        method: "PATCH",
        mimeType: "image/jpeg",
        filename: kind.filename,
        data: data)
      return response?.statusCode == 200
    } catch {
      return false
    }
  }

  private func imageData(for item: PhotosPickerItem, kind: ImageKind) async -> Data? {
    guard
      let imageFile = try? await item.loadTransferable(
        type: StatusEditor.ImageFileTranseferable.self)
    else { return nil }

    let compressor = StatusEditor.Compressor()

    guard let compressedData = await compressor.compressImageFrom(url: imageFile.url),
      let image = UIImage(data: compressedData),
      let uploadData = try? await compressor.compressImageForUpload(
        image,
        maxSize: 2 * 1024 * 1024,  // 2MB
        maxHeight: kind.maxHeight,
        maxWidth: kind.maxWidth
      )
    else {
      return nil
    }

    return uploadData
  }
}
