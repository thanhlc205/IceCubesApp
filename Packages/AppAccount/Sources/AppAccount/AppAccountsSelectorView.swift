import DesignSystem
import Env
import Models
import SwiftUI

@MainActor
public struct AppAccountsSelectorView: View {
  @Environment(UserPreferences.self) private var preferences
  @Environment(CurrentAccount.self) private var currentAccount
  @Environment(AppAccountsManager.self) private var appAccounts
  @Environment(Theme.self) private var theme

  var routerPath: RouterPath

  @State private var isPresented: Bool = false

  private let accountCreationEnabled: Bool
  private let avatarConfig: AvatarView.FrameConfig

  private let transition: Namespace.ID

  private var showNotificationBadge: Bool {
    appAccounts.availableAccounts
      .filter { $0.id != appAccounts.currentAccount.id }
      .compactMap(\.oauthToken)
      .map { preferences.notificationsCount[$0] ?? 0 }
      .reduce(0, +) > 0
  }

  private var sortedAccounts: [AppAccount] {
    appAccounts.availableAccounts.sorted {
      $0.displayAcct(for: nil) < $1.displayAcct(for: nil)
    }
  }

  private var preferredHeight: CGFloat {
    var baseHeight: CGFloat = 360
    baseHeight += CGFloat(60 * appAccounts.availableAccounts.count)
    return baseHeight
  }

  public init(
    transition: Namespace.ID,
    routerPath: RouterPath,
    accountCreationEnabled: Bool = true,
    avatarConfig: AvatarView.FrameConfig? = nil
  ) {
    self.transition = transition
    self.routerPath = routerPath
    self.accountCreationEnabled = accountCreationEnabled
    self.avatarConfig = avatarConfig ?? .badge
  }

  public var body: some View {
    Button {
      isPresented.toggle()
      HapticManager.shared.fireHaptic(.buttonPress)
    } label: {
      labelView
        .contentShape(.circle)
    }
    .contextMenu {
      ForEach(sortedAccounts, id: \.id) { appAccount in
        Button {
          appAccounts.currentAccount = appAccount
        } label: {
          if appAccounts.currentAccount.id == appAccount.id {
            Label(appAccount.server, systemImage: "checkmark.circle.fill")
              .foregroundStyle(.primary)
            Text(appAccount.displayAcct(for: nil))
          } else {
            Text(appAccount.server)
            Text(appAccount.displayAcct(for: nil))
          }
        }
        .tint(.primary)
      }
    }
    .sheet(
      isPresented: $isPresented,
      content: {
        if #available(iOS 26, *) {
          accountsView
            .presentationDetents([.height(preferredHeight), .large])
            .navigationTransition(
              .zoom(sourceID: CurrentAccount.shared.account?.id ?? "", in: transition)
            )
        } else {
          accountsView.presentationDetents([.height(preferredHeight), .large])
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(16)
        }
      }
    )
    .accessibilityRepresentation {
      Menu("accessibility.app-account.selector.accounts") {}
        .accessibilityHint("accessibility.app-account.selector.accounts.hint")
        .accessibilityRemoveTraits(.isButton)
    }
  }

  @ViewBuilder
  private var labelView: some View {
    Group {
      if let account = currentAccount.account, !currentAccount.isLoadingAccount {
        AvatarView(account.avatar, config: avatarConfig)
      } else {
        AvatarView(config: avatarConfig)
          .redacted(reason: .placeholder)
          .allowsHitTesting(false)
      }
    }.overlay(alignment: .topTrailing) {
      if !currentAccount.followRequests.isEmpty || showNotificationBadge, accountCreationEnabled {
        Circle()
          .fill(Color.red)
          .frame(width: 9, height: 9)
      }
    }
  }

  private var accountsView: some View {
    NavigationStack {
      List {
        Section {
          ForEach(sortedAccounts, id: \.id) { appAccount in
            AppAccountView(
              appAccount: appAccount, isInSettings: false, showBadge: true,
              isParentPresented: $isPresented)
          }
          addAccountButton
            .foregroundStyle(theme.labelColor)
        }
        #if !os(visionOS)
          .listRowBackground(theme.secondaryBackgroundColor)
        #endif

        if accountCreationEnabled {
          Section {
            settingsButton
            aboutButton
            supportButton
          }
          #if os(visionOS)
            .foregroundStyle(theme.labelColor)
          #else
            .foregroundStyle(theme.labelColor)
            .listRowBackground(theme.secondaryBackgroundColor)
          #endif
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .navigationTitle("settings.section.accounts")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          if #available(iOS 26.0, *) {
            Button {
              isPresented.toggle()
            } label: {
              Text("action.done").bold()
            }
            .buttonStyle(.glass)
          } else {
            Button {
              isPresented.toggle()
            } label: {
              Text("action.done").bold()
            }
          }
        }
      }
      .environment(routerPath)
    }
  }

  private var addAccountButton: some View {
    Button {
      isPresented = false
      HapticManager.shared.fireHaptic(.buttonPress)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        routerPath.presentedSheet = .addAccount
      }
    } label: {
      Label("app-account.button.add", systemImage: "person.badge.plus")
    }
  }

  private var settingsButton: some View {
    Button {
      isPresented = false
      HapticManager.shared.fireHaptic(.buttonPress)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        routerPath.presentedSheet = .settings
      }
    } label: {
      Label("tab.settings", systemImage: "gear")
    }
  }

  private var supportButton: some View {
    Button {
      isPresented = false
      HapticManager.shared.fireHaptic(.buttonPress)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        routerPath.presentedSheet = .support
      }
    } label: {
      Label("settings.app.support", systemImage: "wand.and.stars")
    }
  }

  private var aboutButton: some View {
    Button {
      isPresented = false
      HapticManager.shared.fireHaptic(.buttonPress)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        routerPath.presentedSheet = .about
      }
    } label: {
      Label("settings.app.about", systemImage: "info.circle")
    }
  }
}
