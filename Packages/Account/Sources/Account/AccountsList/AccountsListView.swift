import DesignSystem
import Env
import Models
import NetworkClient
import SwiftUI

public enum AccountsListMode {
  case following(accountId: String)
  case followers(accountId: String)
  case favoritedBy(statusId: String)
  case rebloggedBy(statusId: String)
  case accountsList(accounts: [Account])
  case blocked, muted

  var title: LocalizedStringKey {
    switch self {
    case .following:
      "account.following"
    case .followers:
      "account.followers"
    case .favoritedBy:
      "account.favorited-by"
    case .rebloggedBy:
      "account.boosted-by"
    case .accountsList:
      ""
    case .blocked:
      "account.blocked"
    case .muted:
      "account.muted"
    }
  }
}

@MainActor
public struct AccountsListView: View {
  @Environment(Theme.self) private var theme
  @Environment(MastodonClient.self) private var client
  @Environment(CurrentAccount.self) private var currentAccount

  private enum ViewState {
    enum PagingState {
      case hasNextPage(maxId: String), none
    }

    case loading
    case display(
      accounts: [Account],
      relationships: [Relationship],
      nextPageState: PagingState)
    case error(error: Error)
  }

  private let mode: AccountsListMode

  @State private var state = ViewState.loading
  @State private var totalCount: Int?
  @State private var accountId: String?
  @State private var searchQuery: String = ""
  @State private var didAppear: Bool = false

  public init(mode: AccountsListMode) {
    self.mode = mode
  }

  public var body: some View {
    listView
      #if !os(visionOS)
        .scrollContentBackground(.hidden)
        .background(theme.primaryBackgroundColor)
      #endif
      .listStyle(.plain)
      .toolbar {
        ToolbarItem(placement: .principal) {
          VStack {
            Text(mode.title)
              .font(.headline)
            if let count = totalCount {
              Text(String(count))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle(mode.title)
      .navigationBarTitleDisplayMode(.inline)
      .task {
        guard !didAppear else { return }
        didAppear = true
        await fetch()
      }
  }

  @ViewBuilder
  private var listView: some View {
    if currentAccount.account?.id == accountId {
      searchableList
    } else {
      standardList
        .refreshable {
          await fetch()
        }
    }
  }

  private var searchableList: some View {
    List {
      listContent
    }
    .searchable(
      text: $searchQuery,
      placement: .navigationBarDrawer(displayMode: .always)
    )
    .task(id: searchQuery) {
      if !searchQuery.isEmpty {
        await search()
      }
    }
    .onChange(of: searchQuery) { _, newValue in
      if newValue.isEmpty {
        Task {
          await fetch()
        }
      }
    }
  }

  private var standardList: some View {
    List {
      listContent
    }
  }

  @ViewBuilder
  private var listContent: some View {
    switch state {
    case .loading:
      ForEach(Account.placeholders()) { _ in
        AccountsListRow(viewModel: .init(account: .placeholder(), relationShip: .placeholder()))
          .redacted(reason: .placeholder)
          .allowsHitTesting(false)
          #if !os(visionOS)
            .listRowBackground(theme.primaryBackgroundColor)
          #endif
      }
    case let .display(accounts, relationships, nextPageState):
      if case .followers = mode,
        !currentAccount.followRequests.isEmpty
      {
        Section(
          header: Text("account.follow-requests.pending-requests"),
          footer: Text("account.follow-requests.instructions")
            .font(.scaledFootnote)
            .foregroundColor(.secondary)
            .offset(y: -8)
        ) {
          ForEach(currentAccount.followRequests) { account in
            AccountsListRow(
              viewModel: .init(account: account),
              isFollowRequest: true,
              requestUpdated: {
                Task {
                  await fetch()
                }
              }
            )
            #if !os(visionOS)
              .listRowBackground(theme.primaryBackgroundColor)
            #endif
          }
        }
      }
      Section {
        if accounts.isEmpty {
          PlaceholderView(
            iconName: "person.icloud",
            title: "No accounts found",
            message: "This list of accounts is empty"
          )
          .listRowSeparator(.hidden)
        } else {
          ForEach(accounts) { account in
            if let relationship = relationships.first(where: { $0.id == account.id }) {
              AccountsListRow(
                viewModel: .init(
                  account: account,
                  relationShip: relationship))
            }
          }
        }
      }
      #if !os(visionOS)
        .listRowBackground(theme.primaryBackgroundColor)
      #endif

      switch nextPageState {
      case let .hasNextPage(maxId):
        NextPageView {
          try await fetchNextPage(maxId: maxId)
        }
        #if !os(visionOS)
          .listRowBackground(theme.primaryBackgroundColor)
        #endif

      case .none:
        EmptyView()
      }

    case let .error(error):
      Text(error.localizedDescription)
        #if !os(visionOS)
          .listRowBackground(theme.primaryBackgroundColor)
        #endif
    }
  }

  private func nextPageState(for link: LinkHandler?) -> ViewState.PagingState {
    link?.maxId.map { .hasNextPage(maxId: $0) } ?? .none
  }

  private func fetchPage(maxId: String?) async throws -> ([Account], LinkHandler?) {
    switch mode {
    case let .followers(accountId):
      return try await client.getWithLink(endpoint: Accounts.followers(id: accountId, maxId: maxId))
    case let .following(accountId):
      return try await client.getWithLink(endpoint: Accounts.following(id: accountId, maxId: maxId))
    case let .rebloggedBy(statusId):
      return try await client.getWithLink(
        endpoint: Statuses.rebloggedBy(id: statusId, maxId: maxId))
    case let .favoritedBy(statusId):
      return try await client.getWithLink(
        endpoint: Statuses.favoritedBy(id: statusId, maxId: maxId))
    case let .accountsList(accounts):
      return (maxId == nil ? accounts : [], nil)
    case .blocked:
      return try await client.getWithLink(endpoint: Accounts.blockList(maxId: maxId))
    case .muted:
      return try await client.getWithLink(endpoint: Accounts.muteList(maxId: maxId))
    }
  }

  private func fetch() async {
    do {
      state = .loading
      switch mode {
      case let .followers(id):
        let account: Account = try await client.get(endpoint: Accounts.accounts(id: id))
        totalCount = account.followersCount
      case let .following(id):
        accountId = id
        let account: Account = try await client.get(endpoint: Accounts.accounts(id: id))
        totalCount = account.followingCount
      default:
        break
      }
      let (accounts, link) = try await fetchPage(maxId: nil)
      let relationships: [Relationship] = try await client.get(
        endpoint: Accounts.relationships(ids: accounts.map(\.id)))
      state = .display(
        accounts: accounts,
        relationships: relationships,
        nextPageState: nextPageState(for: link))
    } catch {
      guard !Task.isCancelled else { return }
      state = .error(error: error)
    }
  }

  private func fetchNextPage(maxId: String) async throws {
    let (newAccounts, link) = try await fetchPage(maxId: maxId)
    let newRelationships: [Relationship] =
      try await client.get(endpoint: Accounts.relationships(ids: newAccounts.map(\.id)))
    guard case let .display(accounts, relationships, _) = state else { return }
    state = .display(
      accounts: accounts + newAccounts,
      relationships: relationships + newRelationships,
      nextPageState: nextPageState(for: link))
  }

  private func search() async {
    guard !searchQuery.isEmpty else { return }
    do {
      try await Task.sleep(for: .milliseconds(250))
      state = .loading
      let results: SearchResults = try await client.get(
        endpoint: Search.search(
          query: searchQuery,
          type: .accounts,
          offset: nil,
          following: true),
        forceVersion: .v2)
      let relationships: [Relationship] =
        try await client.get(endpoint: Accounts.relationships(ids: results.accounts.map(\.id)))
      withAnimation {
        state = .display(
          accounts: results.accounts,
          relationships: relationships,
          nextPageState: .none)
      }
    } catch {
      guard !Task.isCancelled else { return }
      state = .error(error: error)
    }
  }
}

#Preview {
  List {
    AccountsListRow(
      viewModel: .init(
        account: .placeholder(),
        relationShip: .placeholder()))
  }
  .listStyle(.plain)
  .withPreviewsEnv()
  .environment(Theme.shared)
}
