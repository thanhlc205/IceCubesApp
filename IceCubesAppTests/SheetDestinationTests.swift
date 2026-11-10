import Env
import Foundation
@testable import Ice_Cubes
import Models
import NetworkStubs
import Testing
import UIKit

extension AppTests {
  /// Opens every `SheetDestination` through `withSheetDestinations` and checks that it shows
  /// and closes. A screen that reads a service nobody injected stops the app, which fails the run.
  @MainActor
  struct SheetDestinationTests {
    init() {
      StubServer.install(everyHost: true)
      StubServer.reset()
    }

    @Test(arguments: Sheet.allCases)
    func sheetOpensAndCloses(_ sheet: Sheet) async throws {
      let harness = try RouterHarness()
      defer { harness.close() }

      harness.routerPath.presentedSheet = try sheet.destination()
      #expect(try await harness.waitUntil { harness.presentedController != nil }, "Never shown")
      // Lets the sheet's body and its first tasks run before it closes.
      try await Task.sleep(for: .milliseconds(300))

      harness.routerPath.presentedSheet = nil
      #expect(try await harness.waitUntil { harness.presentedController == nil }, "Never closed")
    }

    @Test func everySampleStandsForItsOwnSheet() throws {
      for sheet in Sheet.allCases {
        #expect(try Sheet(for: sheet.destination()) == sheet)
      }
    }
  }
}

/// One sample of every `SheetDestination`. `init(for:)` has no `default`, so a new sheet
/// doesn't compile until it gets a sample here.
enum Sheet: String, CaseIterable, Sendable {
  case newStatusEditor, prefilledStatusEditor, imageURL, editStatusEditor, replyToStatusEditor
  case quoteStatusEditor, quoteLinkStatusEditor, mentionStatusEditor
  case listCreate, listEdit, listAddAccount, addAccount, addRemoteLocalTimeline, addTagGroup
  case statusEditHistory, settings, about, support, accountPushNotficationsSettings, report
  case shareImage, editTagGroup, timelineContentFilter, accountEditInfo, accountFiltersList

  init(for destination: SheetDestination) {
    switch destination {
    case .newStatusEditor: self = .newStatusEditor
    case .prefilledStatusEditor: self = .prefilledStatusEditor
    case .imageURL: self = .imageURL
    case .editStatusEditor: self = .editStatusEditor
    case .replyToStatusEditor: self = .replyToStatusEditor
    case .quoteStatusEditor: self = .quoteStatusEditor
    case .quoteLinkStatusEditor: self = .quoteLinkStatusEditor
    case .mentionStatusEditor: self = .mentionStatusEditor
    case .listCreate: self = .listCreate
    case .listEdit: self = .listEdit
    case .listAddAccount: self = .listAddAccount
    case .addAccount: self = .addAccount
    case .addRemoteLocalTimeline: self = .addRemoteLocalTimeline
    case .addTagGroup: self = .addTagGroup
    case .statusEditHistory: self = .statusEditHistory
    case .settings: self = .settings
    case .about: self = .about
    case .support: self = .support
    case .accountPushNotficationsSettings: self = .accountPushNotficationsSettings
    case .report: self = .report
    case .shareImage: self = .shareImage
    case .editTagGroup: self = .editTagGroup
    case .timelineContentFilter: self = .timelineContentFilter
    case .accountEditInfo: self = .accountEditInfo
    case .accountFiltersList: self = .accountFiltersList
    }
  }

  func destination() throws -> SheetDestination {
    switch self {
    case .newStatusEditor:
      .newStatusEditor(visibility: .pub)
    case .prefilledStatusEditor:
      .prefilledStatusEditor(text: "Hello", visibility: .pub)
    case .imageURL:
      .imageURL(urls: [], caption: nil, altTexts: nil, visibility: .pub)
    case .editStatusEditor:
      try .editStatusEditor(status: Fixture.decode(Fixture.status("401")))
    case .replyToStatusEditor:
      try .replyToStatusEditor(status: Fixture.decode(Fixture.status("402")))
    case .quoteStatusEditor:
      try .quoteStatusEditor(status: Fixture.decode(Fixture.status("403")))
    case .quoteLinkStatusEditor:
      .quoteLinkStatusEditor(link: URL(string: "https://example.com/article")!)
    case .mentionStatusEditor:
      try .mentionStatusEditor(account: Fixture.decode(Fixture.account("404")), visibility: .pub)
    case .listCreate:
      .listCreate
    case .listEdit:
      try .listEdit(list: Fixture.decode(Fixture.list("405")))
    case .listAddAccount:
      try .listAddAccount(account: Fixture.decode(Fixture.account("406")))
    case .addAccount:
      .addAccount
    case .addRemoteLocalTimeline:
      .addRemoteLocalTimeline
    case .addTagGroup:
      .addTagGroup
    case .statusEditHistory:
      .statusEditHistory(status: "407")
    case .settings:
      .settings
    case .about:
      .about
    case .support:
      .support
    case .accountPushNotficationsSettings:
      .accountPushNotficationsSettings
    case .report:
      try .report(status: Fixture.decode(Fixture.status("408")))
    case .shareImage:
      try .shareImage(image: UIImage(systemName: "photo")!, status: Fixture.decode(Fixture.status("409")))
    case .editTagGroup:
      .editTagGroup(tagGroup: TagGroup(title: "Swift", symbolName: "swift", tags: ["swift"]), onSaved: nil)
    case .timelineContentFilter:
      .timelineContentFilter
    case .accountEditInfo:
      .accountEditInfo
    case .accountFiltersList:
      .accountFiltersList
    }
  }
}
