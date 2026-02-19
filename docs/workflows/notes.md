# Notes

Runtime discoveries, edge cases, and gotchas found during implementation. Updated by agents across all phases and sessions. Always loaded into context at session start.

---

## Phase 1 — Skeleton

**Status:** Complete ✅

### Discoveries

1. **Nib-less AppKit lifecycle requires custom `static func main()`** — `@main` on `NSApplicationDelegate` calls `NSApplicationMain()`, which only connects the delegate via a main nib. Without a nib, override `static func main()` to create `NSApplication.shared`, set the delegate, and call `app.run()`. Updated in conventions.md §5.

2. **`NSPrincipalClass` must be set explicitly** — SwiftUI template's auto-generated Info.plist omits it. Added `INFOPLIST_KEY_NSPrincipalClass = NSApplication` to both Debug and Release build settings in the Xcode project.

3. **App Sandbox remaps `/tmp/`** — `ENABLE_APP_SANDBOX = YES` redirects `/tmp/` to `~/Library/Containers/com.uzunu.aslan-browser/Data/tmp/`. Use `NSTemporaryDirectory()` for temp file writes. The Unix socket path `/tmp/aslan-browser.sock` will conflict with sandbox in Phase 2.

4. **`com.apple.security.network.client` entitlement required** — Without it, WKWebView silently fails to load any URL under sandbox.

5. **`webView.title` may be empty at `didFinish` time** — Title is parsed after the navigation delegate callback. Use `document.title` via JS eval for reliable title retrieval immediately after navigation.

6. **Sync conflict files break builds** — Syncthing `.sync-conflict-*.swift` files get auto-included by `PBXFileSystemSynchronizedRootGroup`, causing duplicate type errors. Delete on sight. Consider adding a `.gitignore` or `.stignore` pattern.

---

## Phase 2 — Socket Server

**Status:** Complete ✅

### Decisions

1. **Sandbox disabled** — Set `ENABLE_APP_SANDBOX = NO` to allow Unix socket at `/tmp/aslan-browser.sock`. Sandbox remapped `/tmp/` to container-specific path, making the socket unreachable by external clients. Acceptable tradeoff for a local developer/agent tool.

2. **Custom `LineBasedFrameDecoder`** — SwiftNIO's `LineBasedFrameDecoder` is in `swift-nio-extras`, not core `swift-nio`. Implemented a simple 20-line decoder in `SocketServer.swift` rather than adding another dependency. Follows YAGNI/minimal-deps convention.

3. **`BrowserError` extracted to `Models/BrowserError.swift`** — Moved out of `BrowserTab.swift` into its own file. Added `tabNotFound` and `timeout` cases for future use. Each case maps to a JSON-RPC error code via `.rpcError` computed property.

### Discoveries

1. **NIO → MainActor dispatch pattern** — `JSONRPCHandler.channelRead` runs on the NIO event loop. Dispatches to `@MainActor` via `Task { @MainActor in ... }` for all `BrowserTab` calls. Response is written back via `context.eventLoop.execute { ... }` to return to the event loop for NIO writes.

2. **`RPCParseError` vs `RPCError`** — Two distinct error types: `RPCParseError` for JSON parsing failures (thrown during `RPCRequest.parse`), `RPCError` for JSON-RPC protocol errors (thrown during routing/dispatch). `RPCParseError.invalidJSON` maps to `-32700`, `RPCParseError.invalidRequest` maps to `-32600`.

3. **Socket cleanup** — `SocketServer.removeStaleSocket()` called on both startup and shutdown. `applicationWillTerminate` calls `socketServer?.stop()` for clean shutdown.

4. **`ENABLE_USER_SCRIPT_SANDBOXING` must be `NO`** — Xcode defaults this to `YES`. It sandboxes WKUserScript execution, which blocks the ScriptBridge user scripts from accessing page globals. Disabled in both Debug and Release base build settings.

5. **WebContent process sandbox warnings are harmless noise** — WKWebView spawns a `WebContent` subprocess with Apple's own sandbox. Errors about pasteboard, launchservicesd, AudioComponent, and IconRendering are internal Apple framework noise. They don't affect browsing, navigation, JS eval, or screenshots. Cannot be suppressed.

6. **Window restoration warning** — `NSWindowRestoration` "Unable to find className=(null)" appears because AppKit tries to restore previously saved window state. Suppressed by setting `NSQuitAlwaysKeepsWindows = false` in UserDefaults before `app.run()`.

### Architecture

Socket server running on `/tmp/aslan-browser.sock`. JSON-RPC methods: `navigate`, `evaluate`, `screenshot`, `getTitle`, `getURL`.

Pipeline: `LineBasedFrameDecoder` → `JSONRPCHandler` → `MethodRouter` → `BrowserTab`

### Files Added
- `aslan-browser/SocketServer.swift` — NIO Unix socket + LineBasedFrameDecoder
- `aslan-browser/JSONRPCHandler.swift` — ChannelInboundHandler, JSON-RPC parse/dispatch
- `aslan-browser/MethodRouter.swift` — Maps method names → BrowserTab calls
- `aslan-browser/Models/RPCMessage.swift` — RPCRequest, RPCResponse, RPCErrorResponse, RPCError
- `aslan-browser/Models/BrowserError.swift` — Domain error enum with RPC code mapping
- `tests/test_socket.py` — Integration test (8 tests, all passing)

---

## Phase 3 — ScriptBridge + Readiness Detection

**Status:** Complete ✅

### Decisions

1. **ScriptBridge as enum with static properties** — `ScriptBridge` is an enum (no instances) with a static `injectedJS` computed property and `makeUserScript()` factory. All JS is one monolithic IIFE string.

2. **ScriptMessageHandler as separate class** — `WKScriptMessageHandler` conformance on a dedicated `ScriptMessageHandler` class (not BrowserTab directly) to avoid `nonisolated` conflicts. Uses a callback closure to forward to BrowserTab's `@MainActor` context.

3. **Idle continuation tracking via Int IDs** — `CheckedContinuation` isn't `Equatable`, so `waitForIdle()` uses incrementing integer IDs as dictionary keys to track and remove individual continuations on timeout.

4. **Network starts as idle** — `networkIdle` defaults to `true` since no requests are pending before the page starts loading. The fetch/XHR monkey-patches will set it to `false` when requests begin.

### Discoveries

1. **Script injection timing** — `WKUserScript` with `.atDocumentEnd` runs after the DOM is parsed but before all subresources (images, fonts) finish loading. This is the right timing: the bridge is available for MutationObserver setup and network tracking before the page's own JS runs heavy async work.

2. **MutationObserver auto-starts** — The DOM stability observer starts immediately when the script injects. The initial debounce timer fires after 500ms of quiet, which for simple pages means `domStable` is posted shortly after load.

3. **`waitForSelector` uses `callAsyncJavaScript` Promise handling** — The JS function returns a Promise. `callAsyncJavaScript` natively awaits Promises, so the Swift side just awaits the result. On timeout, the Promise rejects, which becomes a thrown error in Swift.

4. **`waitUntil: "idle"` re-fetches title** — After `waitForIdle()` completes, the title is re-read via `document.title` because SPAs may update the title after initial load.

### Architecture

ScriptBridge injects JS at document end into `window.__agent` namespace:
- `post(type, data)` — sends messages to Swift via `webkit.messageHandlers.agent`
- Network tracking — monkey-patched `fetch` and `XMLHttpRequest`, posts `networkIdle`/`networkBusy`
- DOM stability — `MutationObserver` with configurable debounce (default 500ms), posts `domStable`
- `waitForSelector(selector, timeoutMs)` — returns Promise, uses MutationObserver

BrowserTab readiness state: `didFinishNavigation` + `domStable` + `networkIdle` + `readyStateComplete`

JSON-RPC methods added: `waitForSelector`. Navigate updated with `waitUntil` param (`none`/`load`/`idle`).

### Files Added
- `aslan-browser/ScriptBridge.swift` — JS bridge source as Swift string literals

### Files Modified
- `aslan-browser/BrowserTab.swift` — User script injection, message handler, readiness tracking, waitForIdle, waitForSelector, navigate waitUntil
- `aslan-browser/MethodRouter.swift` — waitForSelector method, navigate waitUntil/timeout params
