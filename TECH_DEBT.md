# Tech-debt register

Last reviewed: 2026-11-07

This is the list of known technical debt in IceCubesApp, scored and ordered so it can be paid down alongside feature work. Update the **Status** column as items move, and re-measure the baseline counts at the bottom when you finish one.

## How items are scored

Each item gets three scores from 1 to 5:

- **I (impact):** how much it slows development down.
- **R (risk):** what happens if it's left alone.
- **E (effort):** how hard it is to fix.

**Score = (I + R) × (6 − E).** Cheap fixes for risky problems rank highest.

The scores assume this fork will ship. If it stays a personal build, #4 drops to about 12, and the Release-keychain part of #1 matters less. The settings-sharing part of #1 still applies.

## Register

| # | Debt item | Type | I | R | E | Score | Effort | Why it matters | Status |
|---|---|---|---|---|---|---|---|---|---|
| 1 | App-group and keychain IDs hardcoded to the upstream developer's identity | Infra | 4 | 5 | 2 | **36** | ~3 h | Builds with another bundle prefix don't share settings with the extensions; a Release build on a device would probably fail to save logins, with no error shown | Done (Phase 0) |
| 2 | No CI job builds or tests pull requests | Infra | 4 | 5 | 3 | **27** | ~1 day | PRs merge after an AI review that can't compile them; none of the 120 tests run | Done (Phase 1) |
| 3 | `CLAUDE.md` is stale, and project conventions live only in one person's local Claude memory | Docs | 3 | 2 | 1 | **25** | ~1 h | Claude sessions and the PR reviewer start with wrong build commands and don't know the localization rules | Done (Phase 0) |
| 4 | Upstream's service keys and IDs in the source | Infra | 2 | 4 | 2 | **24** | ~2 h | Each launch sends telemetry to an account this fork doesn't control; a shipped build's purchases would go there too | Done (Phase 0) |
| 5 | Errors are swallowed instead of logged or shown | Code | 3 | 4 | 3 | **21** | ~1 day for a first pass | Failures look like nothing happened, to users and to developers | First pass done (Phase 1) |
| 6 | 7 of 13 packages have no tests, and the app has no test target | Test | 3 | 4 | 3 | **21** | 1–2 days for the first two suites | Notifications and account switching change with no safety net | Three suites done: notifications, accounts, `AppRegistry` (Phase 1) |
| 7 | EmojiText follows a branch on a fork | Dependency | 1 | 3 | 1 | **20** | 15 min | The next dependency update moves it silently; if the branch is deleted, the build breaks | Done (Phase 0) |
| 8 | Two hand-kept lists of injected services, which already differ | Architecture | 2 | 3 | 2 | **20** | ~½ day | A service added to only one list crashes any sheet or window that reads it | Open |
| 9 | `asyncAfter` timing hacks | Code | 2 | 3 | 2 | **20** | ~½ day | On slow devices, steps can run in the wrong order | Open |
| 10 | `@unchecked Sendable` opt-outs | Code | 1 | 3 | 2 | **16** | ~2 h | Each one turns off Swift 6's data-race checking for that type | Open |
| 11 | `.swiftformat` exists but nothing enforces it | Infra | 2 | 1 | 1 | **15** | ~1 h | Formatting noise in diffs and reviews | SwiftFormat chosen; reformat pending |
| 12 | `TimelineViewModel` is 846 lines | Architecture | 4 | 3 | 4 | **14** | 3–5 days | Every timeline feature lands in it; marker sync alone added 167 lines | Open |
| 13 | Six small ViewModels left | Architecture | 2 | 1 | 2 | **12** | 1–2 days total | Finishes the migration `CLAUDE.md` asks for | Open |
| 14 | Singletons called directly via `.shared` | Architecture | 3 | 2 | 4 | **10** | Ongoing | Previews and tests can't swap services out | Open |
| 15 | `EditorStore` and `UserPreferences` are oversized | Code | 3 | 2 | 4 | **10** | 2–3 days each | Hard to change the composer or settings without side effects | Open |
| 16 | `Env` holds a bit of everything, and 10 packages depend on it | Architecture | 2 | 1 | 3 | **9** | ~1 day | Any edit to `Env` rebuilds nearly everything | Open |
| 17 | Leftover Combine and NotificationCenter events | Code | 1 | 1 | 2 | **8** | ~½ day | Two extra event systems alongside `@Observable` | Open |
| 18 | `StatusRowViewModel` and `StatusDetailViewModel` | Architecture | 2 | 3 | 5 | **5** | 3–5 days | Created for every row and sensitive to scrolling performance | Open |

## Item details

### 1. App-group and keychain IDs hardcoded to upstream's identity
- **Evidence:** the entitlements derive both IDs from build settings (`group.$(BUNDLE_ID_PREFIX).IceCubesApp` and `$(AppIdentifierPrefix)$(BUNDLE_ID_PREFIX).IceCubesApp`). The code used fixed strings instead:
  - `UserPreferences.sharedDefault` used `"group.com.thomasricouard.IceCubesApp"` ([UserPreferences.swift](Packages/Env/Sources/Env/UserPreferences.swift)).
  - `AppInfo.keychainGroup` was `"346J38YKE3.com.thomasricouard.IceCubesApp"` ([App.swift](Packages/Models/Sources/Models/App/App.swift)).
- **Effect:** with any other `BUNDLE_ID_PREFIX`, the shared settings stay inside the app and the extensions never see them. The keychain access group is only applied when building `!DEBUG && !targetEnvironment(simulator)` ([AppAccount.swift](Packages/AppAccount/Sources/AppAccount/AppAccount.swift), `PushNotificationsService.swift`, `DeepLUserAPIHandler.swift`). So a Release build on a device would probably fail to save accounts, and `AppAccountsManager.add(account:)` hides that failure with `catch {}`.
- **Fix:** add `AppGroupIdentifier` and `KeychainAccessGroup` keys to every target's Info.plist, set from build settings. Read them at runtime with `Bundle.main.object(forInfoDictionaryKey:)`.
- **Done (2026-11-07):** all five Info.plists declare both keys. `AppInfo.appGroup` and `AppInfo.keychainGroup` read them and return `nil` when they're missing, empty or unexpanded. Upstream's own builds get the same values as before. A build with a different prefix now writes the last-used account and notification counts to its real app group, so its first launch after this change may open on a different account.

### 2. No CI job builds or tests pull requests
- **Evidence:** `.github/workflows/` contains only `claude-code-review.yml` (runs on Ubuntu, can't compile), `claude.yml`, and `validate_translations.yml`.
- **Fix:** add a macOS workflow that builds the `IceCubesApp` scheme for the simulator, runs the package test schemes, and runs `swiftformat --lint .`.
- **Catch:** [AppView.swift](IceCubesApp/App/Main/AppView.swift) uses `#available(iOS 27.0, visionOS 27.0, *)`, so the runner needs the iOS 27 SDK. If GitHub's hosted macOS images don't have it, use Xcode Cloud (`ci_scripts/` already exists) or a self-hosted runner.
- **Done (2026-11-07):** `.github/workflows/build-and-test.yml` runs on GitHub's `xcode-27` image (public preview). On every pull request and every push to `main` it:
  - selects Xcode 27.2;
  - builds `IceCubesApp` unsigned from the xcconfig template;
  - runs all six test schemes on the iOS 27.0 iPhone Air simulator, because the image has no 27.2 runtime;
  - caches `SourcePackages` and resolves strictly from `Package.resolved`.
  
  The `swiftformat --lint .` step waits for the one-time reformat in #11.

### 3. `CLAUDE.md` is stale; conventions live in local memory
- **Evidence:** [CLAUDE.md](CLAUDE.md) is out of date in five ways:
  - build paths point at `/Users/thomas/...`;
  - it uses `mcp__XcodeBuildMCP__…` tool names;
  - it calls the network package "Network" (it's `NetworkClient`);
  - it leaves out the AppAccount, Conversations, Explore and Lists packages;
  - it implies the packages target macOS (the Mac build is Mac Catalyst).
- **Conventions to move into it:**
  - new strings get symbolic keys (for example `settings.timeline.sync-position`) with `en` and `en-GB` values;
  - edits to `Localizable.xcstrings` must leave the rest of the file byte-identical;
  - simulator builds must be signed, not built with `CODE_SIGNING_ALLOWED=NO`, or logins disappear on reinstall.
- **Fix:** rewrite the build/test section for the tools actually in use, list all 13 packages, and add the conventions. `AGENTS.MD` is a symlink to `CLAUDE.md`, so one edit covers both.
- **Done (2026-11-07):** `CLAUDE.md` now has Setup, Build and Test (`xcodebuild`, signed app builds, test schemes), Localization, and an Architecture section covering all 13 packages, routing and dependency injection. Its formatting section warns against reformatting whole files.

### 4. Upstream's service keys and IDs in the source
- **Evidence:**
  - the RevenueCat API key and WishKit ID are in [IceCubesApp.swift](IceCubesApp/App/Main/IceCubesApp.swift) (`setupRevenueCat`, `AppDelegate`);
  - the TelemetryDeck app ID is in [Telemetry.swift](Packages/Env/Sources/Env/Telemetry.swift), and telemetry isn't turned off in Debug builds;
  - an instances.social API token is in [InstanceSocialClient.swift](Packages/NetworkClient/Sources/NetworkClient/InstanceSocialClient.swift).
- **Fix:** move them into the gitignored `IceCubesApp.xcconfig`, exposed through Info.plist. Either use this fork's own accounts, or turn telemetry and purchases off when no key is set.
- **Done (2026-11-07):** the keys now live in a gitignored `Secrets.xcconfig` (template: `Secrets.xcconfig.template`). Both `IceCubesApp.xcconfig` and `IceCubesApp-release.xcconfig` include it optionally. The app's Info.plist passes the keys to `AppInfo`. Each service stays off without its key:
  - TelemetryDeck isn't started;
  - RevenueCat isn't configured, and both Support entries are hidden;
  - WishKit isn't configured, and Feature Requests is hidden;
  - the add-account server list stays empty.

### 5. Errors are swallowed
- **Evidence:** 51 empty `catch {}` blocks and 66 `try? await`. Only 3 files use `os.Logger`.
- **Fix:** add a `Logger` per package. Show failed user actions (post, follow, boost, login) through the existing `ToastCenter`. After that, add no new empty catches (see the baseline below).
- **First pass (2026-11-10):**
  - **Loggers:** `Logger.env`, `Logger.account` and `Logger.app`, subsystem `com.icecubesapp`. Other packages get theirs when they first log.
  - **Boost, favourite and bookmark:** when a request fails, `StatusDataController` puts the post back, logs the error and rethrows it. The status row views catch the error and show a red toast, such as "Couldn't boost the post".
  - **Count bug fixed:** the old rollback moved the count the wrong way. A failed favourite left the count 2 above where it started, and a failed unfavourite left it 2 below. Tests in `EnvTests` caught both before the fix.
  - **Follow and unfollow:** `FollowButtonViewModel` logs the error and rethrows it. `FollowButton` shows a toast, and the button still shakes.
  - **Sign-in:** a failure shows an inline message on the add-account screen. A toast there would be hidden behind the sheet. Closing the sign-in page shows nothing.
  - **Posting:** it already showed a failure toast and saved a draft, so it's unchanged.
  - **Toast text:** the toast's message is the server's explanation or the connection problem. Other errors get no message.
  - **Strings:** the 9 new ones are translated into every language.
  - **Counts:** `try? await` went from 66 to 64, and files using `Logger` from 3 to 6.
- **Toast slot:** `ToastCenter` shows one toast at a time. A failure doesn't replace a progress toast, such as a post being sent, so the post's own result still appears. The failure is only logged then.
- **Still silent:**
  - The account menu's unblock, unmute, mute, notify and show-boosts actions (`AccountDetailContextMenu`, 7 empty catches).
  - Favourite, boost or bookmark on a post from another server, when it can't be fetched from the user's server first (`StatusRowActionsView.handleAction`).
  - Favourite and bookmark in direct messages (`ConversationMessageView`, 2 empty catches; `ConversationsListView`, catches that hold only a comment).
  - A failed follow inside a sheet (the list editor, About, instance info): the button shakes, but the toast draws behind the sheet.
  - A follow or unfollow the server refuses. `MastodonClient` decodes a response before it checks the status code, and `Relationship` gives every field a default, so the error body `{"error": …}` decodes as an empty relationship. Nothing is thrown, and the button shows "Follow" again with no toast. Only connection errors reach the toast.
  - The other 44 empty catches aren't sorted yet into user actions and background work.

### 6. Missing tests
- **Evidence:** AppAccount, Conversations, DesignSystem, Explore, Lists, MediaUI and Notifications have no tests, and the app target has no test target. The 120 existing tests are in Account, Env, Models, NetworkClient, StatusKit and Timeline.
- **Fix, in this order:** `NotificationsListDataSource` (512 lines of grouping and pagination), then `AppAccountsManager` (switching, adding and deleting accounts), then the destination-to-view mapping in `AppRegistry`.
- **Progress (2026-11-09):**
  - `NotificationsTests` (20 tests) cover `NotificationsListDataSource` on both notification APIs: grouping, type filters, filtered statuses, paging, pull to refresh, streamed notifications and the read marker. They run a real `MastodonClient`, and a `URLProtocol` stub answers its requests with Mastodon-shaped JSON.
  - `AppAccountTests` (7 tests) cover adding, switching and deleting accounts in `AppAccountsManager`.
  - CI runs both schemes. Package tests went from 120 to 147.
  - Each suite was checked by breaking the code on purpose: all 13 deliberate bugs made a test fail.
  - The suites add one `.shared` call to the baseline count: the notification tests must set the `CurrentInstance` singleton that the data source reads (#14).
- **Found while testing:**
  - Before Mastodon 4.3 the app groups notifications itself, and it offers another page only when the grouped rows fill a page. A full page of 30 that groups into 29 rows shows no more, so older notifications can't be reached. This path is used whenever the server's version reads below 4.3 or couldn't be fetched. A test records it with `withKnownIssue`.
  - Package tests can't use the keychain: every write fails with `errSecMissingEntitlement` (-34018). `add(account:)` doesn't notice a failed write, so the account appears but is gone after a relaunch (see #5).
- **Progress (2026-11-09, `AppRegistry`):**
  - The app now has a test target, `IceCubesAppTests`, hosted in the app. The `IceCubesApp` scheme runs it, and so does CI.
  - `RouterDestinationTests` pushes each of the 29 navigation cases through `withAppRouter()`, in a window set up the way a tab sets one up. It checks the screen by the request it sends, such as `/accounts/107/following` for `.following(id: "107")`, or by its title when the screen loads nothing.
  - `SheetDestinationTests` opens and closes each of the 25 sheets through `withSheetDestinations`. These only check that a sheet shows without crashing. They don't tell which screen opened.
  - A destination added to `Router.swift` doesn't compile until the tests have a sample for it.
  - 11 deliberate mapping bugs all made a test fail. Each was caught by the case for its destination. They included swapped modes (following and followers), dropped arguments (the hashtag's account, the notification list's account), wrong screens, and a service missing from the main window, which crashes the screens that read it.
  - The test harness passes the same ten singletons that `IceCubesApp` passes. It uses `.shared` to do it (#14). The baseline below doesn't count them, because it measures neither `IceCubesAppTests/` nor the `.shared` shorthand.
- **Not covered yet:** saving and restoring accounts across launches. That needs an injectable account store in `AppAccountsManager`, or signed runs of the app tests, since CI builds unsigned. The separate editor and media windows, which don't inherit the main window's services (see #8).

### 7. EmojiText follows a branch on a fork
- **Evidence:** `Packages/DesignSystem/Package.swift` depends on `Dimillian/EmojiText` at `branch: "fix-ios26"`. `Package.resolved` currently locks it to commit `3b11459`.
- **Fix:** pin it with `revision:` (or a tag, if upstream releases the fix).
- **Done (2026-11-07):** pinned to `revision: "3b11459a19c9406176a08b0f0599b98f88113296"`, the commit already in use.

### 8. Two hand-kept lists of injected services
- **Evidence:** in [AppRegistry.swift](IceCubesApp/App/Router/AppRegistry.swift), `withAppDependencyGraph` sets up the main window. `withEnvironments()` is used 30 times, for sheets and for the separate editor and media windows. It leaves out `StreamWatcher`, `AppIntentService` and `\.isSupporter`.
- **Fix:** keep one `AppDependencies` value applied by a single modifier. Sheets already inherit the environment from the view that presents them, so most of the 30 sheet calls can probably go. Check each one before removing it.
- **Check:** `SheetDestinationTests` opens every sheet inside the main window's services, so after removing a sheet's `.withEnvironments()` it fails if that sheet needed something only that call provided. The separate windows aren't covered.

### 9. `asyncAfter` timing hacks
- **Evidence:** 12 `DispatchQueue.main.asyncAfter` calls. For example, tapping a push notification switches account, then waits 0.2 s before changing tab ([IceCubesApp+Scene.swift:54](IceCubesApp/App/Main/IceCubesApp+Scene.swift:54)).
- **Fix:** run the steps in a fixed order once the account switch has finished, for example with `.task(id: currentClient.id)` or async code.

### 10. `@unchecked Sendable` opt-outs
- **Evidence:** 8 opt-outs:
  - SwiftUI views and toolbar items in MediaUI: `MediaUIView`, `SavePhotoToolbarItem`, `QuickLookToolbarItem`, `MediaUIShareLink`, `ShareToolbarItem`;
  - other types: `DateFormatterCache`, `HTMLString`, `AppIntentService`.
- **Fix:** remove each opt-out, then fix whatever the compiler reports, or mark the type `@MainActor`. Keep an opt-out only with a comment explaining why it's safe.

### 11. SwiftFormat isn't enforced
- **Evidence:** `.swiftformat` only sets `--indent 2`, and no hook or CI step runs it. Measured on 2026-11-07:
  - SwiftFormat 0.64.6 (`swiftformat --lint .`) would change 303 of 433 files. The most common rules are `indent` (1,849 findings), `wrapArguments` (583), `trailingSpace` (199) and `hoistPatternLet` (194).
  - Apple's `swift-format` 6.4.4 (bundled with Xcode) with its default settings flags 141 files. The most common rules are `Indentation` (360), `TrailingWhitespace` (189) and `UseLetInEveryBoundCaseVariable` (139).
  - The code's style (for example, `else {` on its own line after a multi-line `guard`) is Apple's `swift-format` style, not SwiftFormat's.
- **Size of the one-time reformat** (dry run on a copy, 2026-11-07):
  - `swift-format format` changes 126 files (+975 / −843 lines) and leaves 30 findings to fix by hand. Most of those should be suppressed rather than fixed: 13 snake_case names mirror Mastodon API values, and 9 retroactive conformances are intentional.
  - `swiftformat .` changes 303 files (+4,121 / −3,524 lines).
- **Why it isn't enforced yet:** a format-on-edit hook or a CI lint step would reformat or fail most files, so every change would bury its real diff in reformatting.
- **Decision (2026-11-07):** keep SwiftFormat and `.swiftformat`.
- **Fix:**
  1. Commit Phase 0 first, so the reformat lands in a PR of its own.
  2. In that PR, add `--swiftversion 6.2` to `.swiftformat`. Without it, SwiftFormat warns and turns some features off, so the output would shift again once a version is set. Add `--minversion 0.64.6` too, so everyone formats with at least the version measured here.
  3. Decide on the rules that rewrite code rather than layout. Either keep them and review that part of the diff closely, or turn them off with `--disable` to keep the PR to layout only:

     | Rule | Files affected |
     |---|---|
     | `hoistPatternLet` | 36 |
     | `extensionAccessControl` | 31 |
     | `unusedArguments` | 22 |
     | `contentBuilder` | 20 |
     | `docComments` | 18 |
     | `nestedIf` | 10 |
     | `redundantPublic` | 8 |
     | `repeatedGuard` | 5 |
     | `swiftTestingTestCaseNames` | 5 |
     | `redundantSwiftUIGroup` | 4 |
     | `yodaConditions` | 1 |

  4. Run `swiftformat .`, build, and run all test schemes. Merge while no other branches are open.
  5. Then add `swiftformat --lint .` to CI (#2). Optionally add a Claude Code hook that formats each Swift file after Claude edits it.
- **Setup:** contributors and CI need SwiftFormat installed (`brew install swiftformat`).

### 12. `TimelineViewModel` is 846 lines
- **Evidence:** [TimelineViewModel.swift](Packages/Timeline/Sources/Timeline/View/TimelineViewModel.swift) handles fetching, streaming, pending statuses, marker sync and caching.
- **Fix:** move marker sync and resume, streaming and pending statuses, and pagination into the existing `actors/` layer, one concern per PR, with the 32 Timeline tests as a backstop. Do it the next time you build a timeline feature.

### 13. Six small ViewModels left
- **Evidence:** `StatusPollViewModel`, `ListEditViewModel`, `ListAddAccountViewModel`, `FollowButtonViewModel`, `AccountsListRowViewModel`, `MediaUIAttachmentVideoViewModel`.
- **Fix:** replace each with state owned by the view, the same pattern as the recent `EditAccountViewModel`, `AppAccountViewModel` and `AccountsListViewModel` removals.

### 14. Singletons called directly via `.shared`
- **Evidence:** 17 singleton declarations and 248 direct `.shared` calls to them. The most-used are `HapticManager` (47), `UserPreferences` (31), `Theme` (31) and `StatusDataControllerProvider` (25).
- **Fix:** only the app and the extensions' entry points use `.shared`. Views read services with `@Environment`; other code receives them as initializer parameters. Convert files as you edit them anyway.

### 15. `EditorStore` and `UserPreferences` are oversized
- **Evidence:** `EditorStore.swift` is 979 lines. `UserPreferences.swift` is 589 lines with 44 `@AppStorage` keys covering display, composer, haptics, translation and notifications.
- **Fix:** split each into focused `@Observable` types. Inject them separately rather than nesting them; `CLAUDE.md` forbids nested `@Observable` objects.

### 16. `Env` holds a bit of everything
- **Evidence:** `Env` contains the router, preferences, push, haptics, sounds, telemetry, toasts and the status data controllers. Nine packages depend on it directly, and MediaUI depends on it through DesignSystem.
- **Fix:** move the router enums and `RouterPath` into a small `Navigation` package first. Then move other services out only where it noticeably cuts rebuild times.

### 17. Leftover Combine and NotificationCenter events
- **Evidence:** 4 files import Combine (`StatusRowViewModel`, `AddAccountsView`, `AddRemoteTimelineView`, `TimelineTab`), and there are 17 NotificationCenter posts or observers.
- **Fix:** replace them with `@Observable` state, `.task`, or `AsyncStream` when you're already editing those files.

### 18. `StatusRowViewModel` and `StatusDetailViewModel`
- **Evidence:** `StatusRowViewModel` is 504 lines, and one is created for every row in every list.
- **Fix:** only take this on if profiling shows a reason, and measure scrolling before and after.

## Phased plan

| Phase | When | Items | Goal |
|---|---|---|---|
| 0: quick wins | This week, about 1 day | #1, #3, #7, #11, and a decision on #4 | Fix the live bug and stop new mistakes |
| 1: safety net | Next 2–3 weeks | #2, #6 (first two suites), #5 (first pass) | CI and tests in place before anything is restructured |
| 2: alongside features | 1–2 months | #8, #9, #10, #13, then #12 | Each feature PR also clears one item in the code it touches |
| 3: fix as you go | Ongoing | #14, #15, #16, #17; #18 only if profiling justifies it | Shrink the debt without a big all-at-once refactor |

## Baseline counts

Counts across all targets (`Packages/`, `IceCubesApp/`, `IceCubesAppIntents/` and the four extensions), excluding `.build/`. They should only ever go down. Once CI exists (#2), a step can compare against this table and fail when a number rises.

| Metric | Baseline (2026-11-07) | Related items |
|---|---|---|
| Empty `catch {}` | 51 | #5 |
| `try? await` | 66 | #5 |
| Files using `os.Logger` | 3 (should go up) | #5 |
| `class …ViewModel` | 9 | #12, #13, #18 |
| Project `.shared` calls | 248 | #14 |
| `static let/var shared` declarations | 17 | #14 |
| `@unchecked Sendable` | 8 | #10 |
| `asyncAfter` | 12 | #9 |
| Files importing Combine | 4 | #17 |
| NotificationCenter posts/observers | 17 | #17 |
| Package tests (`@Test` / `func test`) | 120 (should go up) | #6 |

To re-measure from the repo root:

```bash
SRC=(Packages IceCubesApp IceCubesAppIntents IceCubesAppWidgetsExtension IceCubesNotifications IceCubesShareExtension IceCubesActionExtension)
X=(--include='*.swift' --exclude-dir=.build --exclude-dir=.swiftpm)
grep -rnE 'catch \{\s*\}' "${SRC[@]}" "${X[@]}" | wc -l           # empty catch
grep -rnE 'try\? await' "${SRC[@]}" "${X[@]}" | wc -l             # try? await
grep -rlE 'Logger\(' "${SRC[@]}" "${X[@]}" | wc -l                # files using Logger
grep -rnE 'class [A-Za-z]+ViewModel\b' "${SRC[@]}" "${X[@]}" | wc -l
grep -rnE '@unchecked Sendable' "${SRC[@]}" "${X[@]}" | wc -l
grep -rnE 'asyncAfter' "${SRC[@]}" "${X[@]}" | wc -l
grep -rlE '^import Combine' "${SRC[@]}" "${X[@]}" | wc -l
grep -rnE 'static (var|let) shared\b' "${SRC[@]}" "${X[@]}" | wc -l
grep -rhoE '\b[A-Z][A-Za-z]+\.shared\b' "${SRC[@]}" "${X[@]}" \
  | grep -vE '^(UIApplication|URLSession|UIDevice|URLCache|Purchases|AVAudioSession|ImagePipeline|ImageCache|DataLoader)\.shared' \
  | wc -l                                                          # project .shared calls
grep -rnE 'NotificationCenter\.default\.(post|publisher|addObserver)|\.onReceive\(NotificationCenter' "${SRC[@]}" "${X[@]}" | wc -l
grep -rhE '@Test|func test' Packages/*/Tests | wc -l               # package tests
```
