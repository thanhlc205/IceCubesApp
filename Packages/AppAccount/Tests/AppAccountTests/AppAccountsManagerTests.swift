import Env
import Foundation
import Models
import Testing

@testable import AppAccount

private func makeAccount(_ name: String, createdAt: Double) -> AppAccount {
  AppAccount(
    server: "\(name).example",
    accountName: "\(name)@\(name).example",
    oauthToken: OauthToken(
      accessToken: "token-\(name)", tokenType: "Bearer", scope: "read write follow push",
      createdAt: createdAt))
}

private let alice = makeAccount("alice", createdAt: 1)
private let bob = makeAccount("bob", createdAt: 2)
private let carol = makeAccount("carol", createdAt: 3)

/// Covers the accounts the manager holds in memory. Saving to and restoring from the keychain
/// isn't covered: package tests run without a host app, so every keychain write fails with
/// `errSecMissingEntitlement` (-34018), signed or not, and `add(account:)` doesn't report it.
///
/// Uses the test process's own `UserDefaults`, never the app's, and resets the remembered
/// account before each test. `.serialized` because that value is shared.
@MainActor
@Suite(.serialized)
struct AppAccountsManagerTests {
  init() {
    AppAccount.deleteAll()
    AppAccountsManager.latestCurrentAccountKey = ""
  }

  @Test func startsSignedOutOnTheDefaultServerWithNoSavedAccounts() {
    let manager = AppAccountsManager()

    #expect(manager.availableAccounts.isEmpty)
    #expect(manager.currentAccount.server == "mastodon.social")
    #expect(manager.currentAccount.oauthToken == nil)
    #expect(manager.currentClient.server == "mastodon.social")
    #expect(!manager.currentClient.isAuth)
    #expect(manager.pushAccounts.isEmpty)
  }

  @Test func addingAnAccountListsItAndSwitchesToIt() {
    let manager = AppAccountsManager()

    manager.add(account: alice)

    #expect(manager.availableAccounts == [alice])
    #expect(manager.currentAccount == alice)
    #expect(manager.currentClient.server == "alice.example")
    #expect(manager.currentClient.isAuth)
    #expect(AppAccountsManager.latestCurrentAccountKey == alice.id)
  }

  @Test func switchingAccountsPointsTheClientAtTheNewServer() {
    let manager = AppAccountsManager()
    manager.add(account: alice)
    manager.add(account: bob)
    #expect(manager.currentClient.server == "bob.example")

    manager.currentAccount = alice

    #expect(manager.currentClient.server == "alice.example")
    #expect(manager.currentClient.isAuth)
    #expect(AppAccountsManager.latestCurrentAccountKey == alice.id)
  }

  @Test func deletingTheCurrentAccountSwitchesToTheFirstRemainingOne() {
    let manager = AppAccountsManager()
    manager.add(account: alice)
    manager.add(account: bob)
    manager.add(account: carol)

    manager.delete(account: carol)

    #expect(manager.currentAccount == alice)
    #expect(manager.currentClient.server == "alice.example")
    #expect(manager.availableAccounts == [alice, bob])
    #expect(AppAccountsManager.latestCurrentAccountKey == alice.id)
  }

  @Test func deletingAnotherAccountKeepsTheCurrentOne() {
    let manager = AppAccountsManager()
    manager.add(account: alice)
    manager.add(account: bob)

    manager.delete(account: alice)

    #expect(manager.currentAccount == bob)
    #expect(manager.availableAccounts == [bob])
  }

  @Test func deletingTheLastAccountSignsOutToTheDefaultServer() {
    let manager = AppAccountsManager()
    manager.add(account: alice)

    manager.delete(account: alice)

    #expect(manager.availableAccounts.isEmpty)
    #expect(manager.currentAccount.server == "mastodon.social")
    #expect(manager.currentAccount.oauthToken == nil)
    #expect(!manager.currentClient.isAuth)
  }

  @Test func pushNotificationsAreSetUpOnlyForSignedInAccounts() {
    let manager = AppAccountsManager()
    manager.add(account: alice)
    manager.add(account: AppAccount(server: "guest.example", accountName: nil))

    #expect(
      manager.pushAccounts == [
        PushAccount(
          server: "alice.example", token: alice.oauthToken!, accountName: "alice@alice.example")
      ])
  }
}
