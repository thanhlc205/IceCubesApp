import DesignSystem
import EmojiText
import Env
import Models
import NetworkClient
import SwiftUI

extension AppAccount {
  func displayAcct(for account: Account?) -> String {
    if let accountName {
      accountName
    } else {
      "@\(account?.acct ?? "...")@\(server)"
    }
  }
}

@MainActor
private enum AppAccountCache {
  static var accounts: [String: Account] = [:]
}

@MainActor
public struct AppAccountView: View {
  @Environment(Theme.self) private var theme
  @Environment(RouterPath.self) private var routerPath
  @Environment(AppAccountsManager.self) private var appAccounts
  @Environment(UserPreferences.self) private var preferences

  @State private var appAccount: AppAccount
  @State private var account: Account?

  private let isCompact: Bool
  private let isInSettings: Bool
  private let showBadge: Bool

  @Binding var isParentPresented: Bool

  public init(
    appAccount: AppAccount, isCompact: Bool = false, isInSettings: Bool = true,
    showBadge: Bool = false, isParentPresented: Binding<Bool>
  ) {
    _appAccount = State(initialValue: appAccount)
    self.isCompact = isCompact
    self.isInSettings = isInSettings
    self.showBadge = showBadge
    _isParentPresented = isParentPresented
  }

  public var body: some View {
    Group {
      if isCompact {
        compactView
      } else {
        fullView
      }
    }
    .task {
      await fetchAccount()
    }
  }

  private func fetchAccount() async {
    account = AppAccountCache.accounts[appAccount.id]
    let client = MastodonClient(server: appAccount.server, oauthToken: appAccount.oauthToken)
    guard let fetched: Account = try? await client.get(endpoint: Accounts.verifyCredentials)
    else { return }
    account = fetched
    AppAccountCache.accounts[appAccount.id] = fetched
    if appAccount.accountName == nil {
      appAccount.accountName = "\(fetched.acct)@\(appAccount.server)"
      try? appAccount.save()
    }
  }

  @ViewBuilder
  private var compactView: some View {
    HStack {
      if let account = account {
        AvatarView(account.avatar)
      } else {
        ProgressView()
      }
    }
  }

  private var fullView: some View {
    Button {
      if appAccounts.currentAccount.id == appAccount.id,
        let account = account
      {
        if isInSettings {
          routerPath.navigate(
            to: .accountSettingsWithAccount(account: account, appAccount: appAccount))
          HapticManager.shared.fireHaptic(.buttonPress)
        } else {
          isParentPresented = false
          routerPath.navigate(to: .accountDetailWithAccount(account: account))
          HapticManager.shared.fireHaptic(.buttonPress)
        }
      } else {
        var transation = Transaction()
        transation.disablesAnimations = true
        withTransaction(transation) {
          appAccounts.currentAccount = appAccount
          HapticManager.shared.fireHaptic(.notification(.success))
        }
      }
    } label: {
      HStack {
        if let account = account {
          ZStack(alignment: .topTrailing) {
            AvatarView(account.avatar)
            if appAccount.id == appAccounts.currentAccount.id {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white, .green)
                .offset(x: 5, y: -5)
            } else if showBadge,
              let token = appAccount.oauthToken,
              let notificationsCount = preferences.notificationsCount[token],
              notificationsCount > 0
            {
              ZStack {
                Circle()
                  .fill(.red)
                Text(notificationsCount > 99 ? "99+" : String(notificationsCount))
                  .foregroundColor(.white)
                  .font(.system(size: 9))
              }
              .frame(width: 20, height: 20)
              .offset(x: 5, y: -5)
            }
          }
        } else {
          ProgressView()
          Text(appAccount.accountName ?? appAccount.displayAcct(for: account))
            .font(.scaledSubheadline)
            .foregroundStyle(Color.secondary)
            .padding(.leading, 6)
        }
        VStack(alignment: .leading) {
          if let account = account {
            EmojiTextApp(.init(stringValue: account.safeDisplayName), emojis: account.emojis)
              .foregroundColor(theme.labelColor)
            Text("\(account.username)@\(appAccount.server)")
              .font(.scaledSubheadline)
              .emojiText.size(Font.scaledSubheadlineFont.emojiSize)
              .emojiText.baselineOffset(Font.scaledSubheadlineFont.emojiBaselineOffset)
              .foregroundStyle(Color.secondary)
          }
        }
        if isInSettings {
          Spacer()
          Image(systemName: "chevron.right")
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
