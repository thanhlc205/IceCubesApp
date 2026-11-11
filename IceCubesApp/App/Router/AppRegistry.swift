import Account
import AppAccount
import Conversations
import DesignSystem
import Env
import Explore
import LinkPresentation
import Lists
import MediaUI
import Models
import Notifications
import StatusKit
import SwiftUI
import Timeline

/// The services every window shows. It's the one list of them: the main window, the media sheet,
/// and the editor and media windows on Mac and Vision Pro all apply it with
/// `withAppDependencies(_:)`. Sheets don't need it, because they inherit the services of the view
/// that shows them.
@MainActor
struct AppDependencies {
  let appAccountsManager: AppAccountsManager
  let currentAccount: CurrentAccount
  let currentInstance: CurrentInstance
  let userPreferences: UserPreferences
  let theme: Theme
  let watcher: StreamWatcher
  let pushNotificationsService: PushNotificationsService
  let appIntentService: AppIntentService
  let quickLook: QuickLook
  let toastCenter: ToastCenter
  let isSupporter: Bool
}

@MainActor
extension View {
  func withAppDependencies(_ dependencies: AppDependencies) -> some View {
    environment(dependencies.appAccountsManager)
      .environment(dependencies.appAccountsManager.currentClient)
      .environment(dependencies.quickLook)
      .environment(dependencies.currentAccount)
      .environment(dependencies.currentInstance)
      .environment(dependencies.userPreferences)
      .environment(dependencies.theme)
      .environment(dependencies.watcher)
      .environment(dependencies.pushNotificationsService)
      .environment(dependencies.appIntentService)
      .environment(dependencies.toastCenter)
      .environment(\.isSupporter, dependencies.isSupporter)
  }

  /// The main window's services, and the work that points them at the current account.
  func withAppDependencyGraph(
    _ dependencies: AppDependencies,
    namespace: Namespace.ID
  ) -> some View {
    let appAccountsManager = dependencies.appAccountsManager
    let currentAccount = dependencies.currentAccount
    let currentInstance = dependencies.currentInstance
    let userPreferences = dependencies.userPreferences
    let watcher = dependencies.watcher
    let pushNotificationsService = dependencies.pushNotificationsService
    let quickLook = dependencies.quickLook
    return withAppDependencies(dependencies)
      .task(id: appAccountsManager.currentClient.id) {
        let client = appAccountsManager.currentClient
        quickLook.namespace = namespace
        currentAccount.setClient(client: client)
        currentInstance.setClient(client: client)
        userPreferences.setClient(client: client)
        await currentInstance.fetchCurrentInstance()
        watcher.setClient(
          client: client,
          instanceStreamingURL: currentInstance.instance?.urls?.streamingApi)
        if client.isAuth {
          watcher.watch(streams: [.user, .direct])
        } else {
          watcher.stopWatching()
        }
      }
      .task(id: appAccountsManager.pushAccounts.map(\.token)) {
        pushNotificationsService.tokens = appAccountsManager.pushAccounts.map(\.token)
      }
  }

  func withAppRouter() -> some View {
    navigationDestination(for: RouterDestination.self) { destination in
      switch destination {
      case .accountDetail(let id):
        AccountDetailView(accountId: id)
      case .accountDetailWithAccount(let account):
        AccountDetailView(account: account)
      case .accountSettingsWithAccount(let account, let appAccount):
        AccountSettingsView(account: account, appAccount: appAccount)
      case .accountMediaGridView(let account, let initialMedia):
        AccountDetailMediaGridView(account: account, initialMediaStatuses: initialMedia)
      case .statusDetail(let id):
        StatusDetailView(statusId: id)
      case .statusDetailWithStatus(let status):
        StatusDetailView(status: status)
      case .remoteStatusDetail(let url):
        StatusDetailView(remoteStatusURL: url)
      case .conversationDetail(let conversation):
        ConversationDetailView(conversation: conversation)
      case .hashTag(let tag, let accountId):
        TimelineView(
          timeline: .constant(.hashtag(tag: tag, accountId: accountId)),
          pinnedFilters: .constant([]),
          selectedTagGroup: .constant(nil),
          canFilterTimeline: false)
      case .list(let list):
        TimelineView(
          timeline: .constant(.list(list: list)),
          pinnedFilters: .constant([]),
          selectedTagGroup: .constant(nil),
          canFilterTimeline: false)
      case .collectionDetail(let collection):
        CollectionDetailView(collection: collection)
      case .linkTimeline(let url, let title):
        TimelineView(
          timeline: .constant(.link(url: url, title: title)),
          pinnedFilters: .constant([]),
          selectedTagGroup: .constant(nil),
          canFilterTimeline: false)
      case .quotes(let id):
        TimelineView(
          timeline: .constant(.quotes(statusId: id)),
          pinnedFilters: .constant([]),
          selectedTagGroup: .constant(nil),
          canFilterTimeline: false)
      case .following(let id):
        AccountsListView(mode: .following(accountId: id))
      case .followers(let id):
        AccountsListView(mode: .followers(accountId: id))
      case .favoritedBy(let id):
        AccountsListView(mode: .favoritedBy(statusId: id))
      case .rebloggedBy(let id):
        AccountsListView(mode: .rebloggedBy(statusId: id))
      case .accountsList(let accounts):
        AccountsListView(mode: .accountsList(accounts: accounts))
      case .trendingTimeline:
        TimelineView(
          timeline: .constant(.trending),
          pinnedFilters: .constant([]),
          selectedTagGroup: .constant(nil),
          canFilterTimeline: false)
      case .trendingLinks(let cards):
        TrendingLinksListView(cards: cards)
      case .tagsList(let tags):
        TagsListView(tags: tags)
      case .notificationsRequests:
        NotificationsRequestsListView()
      case .notificationForAccount(let accountId):
        NotificationsListView(
          lockedType: nil,
          lockedAccountId: accountId)
      case .blockedAccounts:
        AccountsListView(mode: .blocked)
      case .mutedAccounts:
        AccountsListView(mode: .muted)
      case .conversations:
        ConversationsListView()
      case .instanceInfo(let instance):
        InstanceInfoView(instance: instance)
      case .metrics:
        AccountMetricsView()
      }
    }
  }

  func withSheetDestinations(
    sheetDestinations: Binding<SheetDestination?>,
    routerPath: RouterPath
  ) -> some View {
    sheet(item: sheetDestinations) { destination in
      Group {
        switch destination {
        case .replyToStatusEditor(let status):
          StatusEditor.MainView(mode: .replyTo(status: status))
        case .newStatusEditor(let visibility):
          StatusEditor.MainView(mode: .new(text: nil, visibility: visibility))
        case .prefilledStatusEditor(let text, let visibility):
          StatusEditor.MainView(mode: .new(text: text, visibility: visibility))
        case .imageURL(let urls, let caption, let altTexts, let visibility):
          StatusEditor.MainView(
            mode: .imageURL(
              urls: urls, caption: caption, altTexts: altTexts, visibility: visibility)
          )
        case .editStatusEditor(let status):
          StatusEditor.MainView(mode: .edit(status: status))
        case .quoteStatusEditor(let status):
          StatusEditor.MainView(mode: .quote(status: status))
        case .quoteLinkStatusEditor(let link):
          StatusEditor.MainView(mode: .quoteLink(link: link))
        case .mentionStatusEditor(let account, let visibility):
          StatusEditor.MainView(mode: .mention(account: account, visibility: visibility))
        case .listCreate:
          ListCreateView()
        case .listEdit(let list):
          ListEditView(list: list)
        case .listAddAccount(let account):
          ListAddAccountView(account: account)
        case .addAccount:
          AddAccountView()
        case .addRemoteLocalTimeline:
          AddRemoteTimelineView()
        case .addTagGroup:
          EditTagGroupView()
        case .statusEditHistory(let status):
          StatusEditHistoryView(statusId: status)
        case .settings:
          SettingsTabs(isModal: true)
            .preferredColorScheme(Theme.shared.selectedScheme == .dark ? .dark : .light)
        case .accountPushNotficationsSettings:
          if let subscription = PushNotificationsService.shared.subscriptions.first(where: {
            $0.account.token == AppAccountsManager.shared.currentAccount.oauthToken
          }) {
            NavigationSheet { PushNotificationsView(subscription: subscription) }
          } else {
            EmptyView()
          }
        case .about:
          NavigationSheet { AboutView() }
        case .support:
          NavigationSheet { SupportAppView() }
        case .report(let status):
          ReportView(status: status)
        case .shareImage(let image, let status):
          ActivityView(image: image, status: status)
        case .editTagGroup(let tagGroup, let onSaved):
          EditTagGroupView(tagGroup: tagGroup, onSaved: onSaved)
        case .timelineContentFilter:
          TimelineContentFilterView()
        case .accountEditInfo:
          EditAccountView()
        case .accountFiltersList:
          FiltersListView()
        }
      }
      .environment(routerPath)
    }
  }

  func withModelContainer() -> some View {
    modelContainer(for: [
      Draft.self,
      LocalTimeline.self,
      TagGroup.self,
      RecentTag.self,
      MetricsNotificationGroup.self,
    ])
  }
}

struct ActivityView: UIViewControllerRepresentable {
  let image: UIImage
  let status: Status

  class LinkDelegate: NSObject, UIActivityItemSource {
    let image: UIImage
    let status: Status

    init(image: UIImage, status: Status) {
      self.image = image
      self.status = status
    }

    func activityViewControllerLinkMetadata(_: UIActivityViewController) -> LPLinkMetadata? {
      let imageProvider = NSItemProvider(object: image)
      let metadata = LPLinkMetadata()
      metadata.imageProvider = imageProvider
      metadata.title = status.reblog?.content.asRawText ?? status.content.asRawText
      return metadata
    }

    func activityViewControllerPlaceholderItem(_: UIActivityViewController) -> Any {
      image
    }

    func activityViewController(
      _: UIActivityViewController,
      itemForActivityType _: UIActivity.ActivityType?
    ) -> Any? {
      nil
    }
  }

  func makeUIViewController(context _: UIViewControllerRepresentableContext<ActivityView>)
    -> UIActivityViewController
  {
    UIActivityViewController(
      activityItems: [image, LinkDelegate(image: image, status: status)],
      applicationActivities: nil)
  }

  func updateUIViewController(
    _: UIActivityViewController, context _: UIViewControllerRepresentableContext<ActivityView>
  ) {}
}

extension URL: @retroactive Identifiable {
  public var id: String {
    absoluteString
  }
}
