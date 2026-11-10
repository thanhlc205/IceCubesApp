# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

IceCubesApp is a multiplatform Mastodon client built entirely in SwiftUI. It runs on iOS, iPadOS, visionOS, and on macOS through Mac Catalyst. The packages declare iOS and visionOS only.

## Setup

- Copy `IceCubesApp.xcconfig.template` to `IceCubesApp.xcconfig` (gitignored) and set `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX`. Debug builds use that file; Release builds use `IceCubesApp-release.xcconfig`.
- The app group (`group.$(BUNDLE_ID_PREFIX).IceCubesApp`) and the keychain access group (`$(AppIdentifierPrefix)$(BUNDLE_ID_PREFIX).IceCubesApp`) come from build settings through each target's Info.plist. Code reads them as `AppInfo.appGroup` and `AppInfo.keychainGroup`. Never hardcode a team ID, bundle prefix or group name in Swift.
- Third-party service keys (RevenueCat, TelemetryDeck, WishKit, instances.social) live in `Secrets.xcconfig` (gitignored; copy `Secrets.xcconfig.template`). They reach code through the app's Info.plist as `AppInfo.revenueCatKey`, `AppInfo.telemetryDeckAppID`, `AppInfo.wishKitAPIKey` and `AppInfo.instancesSocialToken`. Each one is optional: a service without a key stays off, so code must handle `nil`. For example, check `Purchases.isConfigured` before touching `Purchases.shared`.

## Build and Test

Use the MobileBuildMCP tools when they're available, otherwise `xcodebuild`. Any available simulator works (`xcrun simctl list devices available`).

### Build the app
```bash
xcodebuild build -project IceCubesApp.xcodeproj -scheme IceCubesApp -destination 'platform=iOS Simulator,name=iPhone Air,OS=latest'
```
Build the app **signed** (the default). Don't pass `CODE_SIGNING_ALLOWED=NO` for a build you install: an unsigned build has no keychain entitlement, so sign-ins are lost on every reinstall.

### Run tests
Package test schemes: `AccountTests`, `AppAccountTests`, `EnvTests`, `ModelsTests`, `NetworkClientTests`, `NotificationsTests`, `StatusKitTests`, `TimelineTests`. Adding a `.testTarget` to a package's `Package.swift` creates its scheme; add the new scheme to the CI workflow's list.
```bash
xcodebuild test -project IceCubesApp.xcodeproj -scheme TimelineTests -destination 'platform=iOS Simulator,name=iPhone Air,OS=latest' CODE_SIGNING_ALLOWED=NO
```
Skipping signing is fine for test runs. To run one Swift Testing test, pass its name with parentheses, such as `-only-testing:AppAccountTests/AppAccountsManagerTests/addingAnAccountListsItAndSwitchesToIt()`. Without them the filter matches nothing and the run passes with no tests.

- **Network:** to test code that calls `MastodonClient`, answer its requests with a `URLProtocol` stub, as `Packages/Notifications/Tests/NotificationsTests/StubServer.swift` does, and mark the suite `.serialized`.
- **Keychain:** package tests run without a host app, so every keychain write fails with `errSecMissingEntitlement` (-34018), signed or not. Code that saves to the keychain can't be tested at this level yet.

App tests: the `IceCubesApp` scheme's test action runs `IceCubesAppTests/`, a unit-test bundle hosted in the app (`@testable import Ice_Cubes`, the app's module name). Its `RouterHarness` shows `withAppRouter()` and `withSheetDestinations` in a window the way a tab does, inside the main window's services, and its own `StubServer` answers every request.
```bash
xcodebuild test -project IceCubesApp.xcodeproj -scheme IceCubesApp -destination 'platform=iOS Simulator,name=iPhone Air,OS=latest' CODE_SIGNING_ALLOWED=NO
```
- The tests install and launch the real app. An unsigned install has no keychain entitlement, so run them on a simulator without real sign-ins, or build signed.
- A new `RouterDestination` or `SheetDestination` won't compile until `RouterDestinationTests.swift` or `SheetDestinationTests.swift` has a sample for it. Give a navigation destination the request its screen sends first, or its title if it loads nothing.
- Every suite in the target nests in `AppTests`, which is `.serialized`, because they share the stub and the app's singletons.

### CI
`.github/workflows/build-and-test.yml` builds the `IceCubesApp` scheme unsigned and runs the app tests and all eight package test schemes on every pull request and every push to `main`. It runs on GitHub's `xcode-27` image with Xcode 27.2, and tests run on the iOS 27.0 simulator because the image has no 27.2 runtime. A pull request should be green there before it merges.

### Code formatting
The project's formatter is SwiftFormat (`brew install swiftformat`), configured by `.swiftformat` with 2-space indentation. It isn't enforced yet: `swiftformat --lint .` flags 303 of 433 files until a one-time reformat lands in its own PR (#11 in `TECH_DEBT.md`). Until then, match the style of the code around your change, and **don't run SwiftFormat over whole files**: it buries the real change in reformatting.

## Localization

All strings are in `IceCubesApp/Resources/Localization/Localizable.xcstrings`: source `en`, plus `en-GB` and 17 translated languages.

- New strings use symbolic keys: lowercase, dot-separated, hyphenated words, such as `settings.timeline.sync-position` and its footer `settings.timeline.sync-position-footer`. Don't use the English sentence as the key; the older English-keyed strings are legacy.
- Each new key gets `extractionState: "manual"`, an `en` value, an `en-GB` value in British spelling (Favourites, Colour), and every other language, all with `state: "translated"`.
- Edit the catalog without reformatting it. Load it as JSON, insert the new key at its case-insensitive sorted position (not at the end), and write it back with `json.dumps(d, indent=2, ensure_ascii=False, separators=(",", " : "))` and no trailing newline. That matches Xcode's output byte for byte, so the diff shows only the new lines.
- The `validate_translations` workflow checks for missing translations on pull requests.

## Architecture

### Packages
The app target (`IceCubesApp/`) is a thin shell. Features live in 13 local Swift packages under `Packages/`, and dependencies only point downward:

- **Models**: Codable Mastodon types, SwiftData models (`Draft`, `LocalTimeline`, `TagGroup`, `RecentTag`, `MetricsNotificationGroup`), `HTMLString`, `AppInfo`
- **NetworkClient**: `MastodonClient`, one `Endpoint` enum per API area, plus DeepL, OpenAI and instances.social clients
- **Env**: shared `@Observable` services (`CurrentAccount`, `CurrentInstance`, `UserPreferences`, `StreamWatcher`, `PushNotificationsService`, `ToastCenter` and more) and the router (`RouterDestination`, `SheetDestination`, `RouterPath`)
- **DesignSystem**: `Theme`, fonts, avatars, emoji text and reusable components
- **AppAccount**: `AppAccountsManager` (multiple accounts, tokens in the keychain) and the account switcher
- **MediaUI**: the full-screen media viewer
- **StatusKit**: status rows, status detail, the post editor (`EditorStore`), polls and embeds
- **Timeline**: timeline views, plus actors for fetching, filtering, caching (Bodega/SQLite) and Home marker sync
- **Account**, **Notifications**, **Conversations**, **Explore**, **Lists**: feature screens. Explore and Lists also depend on Account.

### How the pieces connect
- **Dependency injection:** `IceCubesApp` owns the shared services and injects them with `withAppDependencyGraph` in `IceCubesApp/App/Router/AppRegistry.swift`. Sheets and the extra Catalyst/visionOS windows use `withEnvironments()`, so a new service has to be added to both.
- **Routing:** feature packages push `RouterDestination` and `SheetDestination` values onto `RouterPath` without importing each other. Only `AppRegistry.swift` maps destinations to views, so a new screen needs a case in `Packages/Env/Sources/Env/Router.swift` and a mapping in `AppRegistry.swift`.
- **Account switching:** setting `AppAccountsManager.currentAccount` creates a new `MastodonClient`, and a `.task(id:)` in `withAppDependencyGraph` points the other services at it.
- **Live updates:** `StreamWatcher` keeps a streaming connection open and publishes `latestEvent`, which the timeline, notification and detail views observe.

### Architectural patterns
The codebase contains legacy MVVM, but **new features should NOT use ViewModels**. Nine remain (`TimelineViewModel`, `StatusRowViewModel`, `StatusDetailViewModel` and six small ones), tracked in `TECH_DEBT.md`.

- **Modern approach:** views as pure state expressions using SwiftUI primitives
- **Environment:** `@Observable` services injected with `.environment(_:)`. In views, prefer `@Environment` over calling `.shared`.
- **Swift Concurrency:** async/await throughout; the packages build in the Swift 6 language mode
- **Errors:** don't add empty `catch {}` blocks. Log with the package's `Logger` (`Logger.env`, `Logger.account`, `Logger.app`; a package without one gets a `Logger+<Package>.swift` with subsystem `com.icecubesapp`). Services, data controllers and view models log and rethrow, and never show UI. The view catches the error and, when something the user did failed, calls `toastCenter.showFailure(title:error:)` on the `ToastCenter` from its environment. Inside a sheet, show the error in the sheet instead, because toasts draw in the main window behind it.

### App extensions and other targets
- **IceCubesNotifications**: decrypts Web Push payloads (relayed through a proxy server for privacy) and formats notifications
- **IceCubesShareExtension**: hosts the post editor for shared content
- **IceCubesActionExtension**: a share-sheet action
- **IceCubesAppWidgetsExtension**: account, mentions, latest posts, hashtag and list widgets
- **IceCubesAppIntents/**: App Intents and Shortcuts, compiled into the app target

### Other details
- **Theme system:** extensive customization with 40+ app icons
- **Translation:** DeepL API and instance-provided translations
- **AI features:** OpenAI integration for alt-text generation

## Tech Debt

`TECH_DEBT.md` lists known debt with scores, a phased plan, and baseline counts (empty `catch {}`, `.shared` calls, ViewModels and more) that should only go down. Don't add to those counts in new code.

## Modern SwiftUI Architecture Guidelines (2025)

### Core Philosophy

- SwiftUI is the default UI paradigm - embrace its declarative nature
- Avoid legacy UIKit patterns and unnecessary abstractions
- Focus on simplicity, clarity, and native data flow
- Let SwiftUI handle the complexity - don't fight the framework
- **No ViewModels** - Use native SwiftUI data flow patterns

### Architecture Principles

#### 1. Native State Management

Use SwiftUI's built-in property wrappers appropriately:
- `@State` - Local, ephemeral view state
- `@Binding` - Two-way data flow between views
- `@Observable` - Shared state (preferred for new code)
- `@Environment` - Dependency injection for app-wide concerns

#### 2. State Ownership

- Views own their local state unless sharing is required
- State flows down, actions flow up
- Keep state as close to where it's used as possible
- Extract shared state only when multiple views need it

Example:
```swift
struct TimelineView: View {
    @Environment(Client.self) private var client
    @State private var viewState: ViewState = .loading

    enum ViewState {
        case loading
        case loaded(statuses: [Status])
        case error(Error)
    }

    var body: some View {
        Group {
            switch viewState {
            case .loading:
                ProgressView()
            case .loaded(let statuses):
                StatusList(statuses: statuses)
            case .error(let error):
                ErrorView(error: error)
            }
        }
        .task {
            await loadTimeline()
        }
    }

    private func loadTimeline() async {
        do {
            let statuses = try await client.getHomeTimeline()
            viewState = .loaded(statuses: statuses)
        } catch {
            viewState = .error(error)
        }
    }
}
```

#### 3. Modern Async Patterns

- Use `async/await` as the default for asynchronous operations
- Leverage `.task` modifier for lifecycle-aware async work
- Handle errors gracefully with try/catch
- Avoid Combine unless absolutely necessary

#### 4. View Composition

- Build UI with small, focused views
- Extract reusable components naturally
- Use view modifiers to encapsulate common styling
- Prefer composition over inheritance

#### 5. Code Organization

- Organize by feature (e.g., Timeline/, Account/, Settings/)
- Keep related code together in the same file when appropriate
- Use extensions to organize large files
- Follow Swift naming conventions consistently

### Build Verification Process
**IMPORTANT**: When editing code, you MUST:

1. Build the project after making changes (see "Build and Test" above)
2. Fix any compilation errors before proceeding
3. Run relevant tests if modifying existing functionality
4. Ensure code follows modern SwiftUI patterns

### Implementation Examples

#### Shared State with @Observable
```swift
@Observable
class AppAccountsManager {
    var currentAccount: Account?
    var availableAccounts: [Account] = []

    func switchAccount(_ account: Account) {
        currentAccount = account
        // Handle account switching
    }
}

// In App file
struct IceCubesApp: App {
    @State private var accountManager = AppAccountsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(accountManager)
        }
    }
}
```

#### Modern Async Data Loading
```swift
struct NotificationsView: View {
    @Environment(Client.self) private var client
    @State private var notifications: [Notification] = []
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        List(notifications) { notification in
            NotificationRow(notification: notification)
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .task {
            await loadNotifications()
        }
        .refreshable {
            await loadNotifications()
        }
    }

    private func loadNotifications() async {
        isLoading = true
        defer { isLoading = false }

        do {
            notifications = try await client.getNotifications()
        } catch {
            self.error = error
        }
    }
}
```

### Best Practices

#### DO:
- Write self-contained views when possible
- Use property wrappers as intended by Apple
- Test logic in isolation, preview UI visually
- Handle loading and error states explicitly
- Keep views focused on presentation
- Use Swift's type system for safety
- Trust SwiftUI's update mechanism

#### DON'T:
- Create ViewModels for every view
- Move state out of views unnecessarily
- Add abstraction layers without clear benefit
- Use Combine for simple async operations
- Fight SwiftUI's update mechanism
- Overcomplicate simple features
- **Nest @Observable objects within other @Observable objects** - This breaks SwiftUI's observation system. Initialize services at the view level instead.

### Testing Strategy

- Unit test business logic in services/clients
- Use SwiftUI Previews for visual testing
- Test @Observable classes independently
- Keep tests simple and focused
- Don't sacrifice code clarity for testability

### Code Style When Editing
- Maintain existing patterns in legacy code
- New features use modern patterns exclusively
- Prefer composition over inheritance
- Keep views focused and single-purpose
- Use descriptive names for state enums
- Write SwiftUI code that looks and feels like SwiftUI
