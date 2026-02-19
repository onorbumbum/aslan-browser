# Aslan Browser — Conventions

Project conventions, architecture decisions, and coding standards. Loaded at the start of every session. This is the single source of truth for how the project is built.

---

## 1. Project Identity

- **Name**: aslan-browser
- **Bundle ID**: `com.uzunu.aslan-browser`
- **What it is**: A native macOS app wrapping WKWebView, exposing a JSON-RPC API over a Unix socket so AI agents can browse the web programmatically.
- **What it is NOT**: A general-purpose browser, a cross-platform tool, a CDP replacement.
- **Socket path**: `/tmp/aslan-browser.sock`
- **Deployment target**: macOS 15.0
- **Swift**: 6.2 (language version 5.0)

---

## 2. Architecture Decisions

These are final decisions. Some differ from the original PRD — corrections are noted with rationale.

| Decision | Choice | Rationale |
|---|---|---|
| UI framework | **AppKit** | This is a service, not a UI app. AppKit gives direct NSWindow control for WKWebView hosting. SwiftUI adds abstraction we don't need. |
| Window visibility | **Visible by default, `--hidden` flag** | Must be able to observe the browser during dev/debug. `--hidden` for production/CI. |
| Server | **SwiftNIO + Unix socket** | Local, fast, no port conflicts, filesystem permissions for security. |
| Protocol | **NDJSON JSON-RPC 2.0** | Newline-delimited JSON over raw socket. No HTTP layer. Simple, fast, easy to implement clients. *(PRD correction: PRD mixed HTTP endpoints with JSON-RPC — unnecessary complexity.)* |
| Screenshots | **Base64 in JSON-RPC response** | Local Unix socket makes base64 overhead negligible (~microseconds for 100KB). One protocol for everything. *(PRD correction: PRD had separate binary endpoint — breaks protocol uniformity for marginal gain.)* |
| Events | **JSON-RPC notifications** | Server→client messages without `id` field. Standard JSON-RPC 2.0. *(PRD correction: PRD used SSE which requires HTTP framing — unnecessary over Unix socket.)* |
| Concurrency | **Swift async/await + @MainActor** | BrowserTab is @MainActor (required by WebKit). NIO handlers dispatch to MainActor for WKWebView calls. |
| Click mechanism | **JS click only** | `querySelector` → `focus` → `click` via JS. Covers 95%+ of cases. No NSEvent synthesis. YAGNI. |
| Tab model | **Tabs in one process** | Simpler than multi-window isolation. Revisit only if real isolation issues arise. |
| App launch | **Started separately** | Agent connects to socket. No auto-launch/subprocess management. YAGNI. |
| Content blocking | **Not included** | YAGNI. Can add via `WKContentRuleList` later if needed. |
| PDF handling | **Not included** | YAGNI. WKWebView renders PDFs natively; no special extraction. |
| DOM quiet timeout | **Configurable, default 500ms** | PRD hardcoded 500ms. Make it a parameter so agents can tune per-site. |

### Protocol Design: NDJSON JSON-RPC 2.0

All communication is newline-delimited JSON-RPC 2.0 over the Unix socket.

**Request** (client → server):
```json
{"jsonrpc":"2.0","id":1,"method":"navigate","params":{"tabId":"tab0","url":"https://example.com"}}
```

**Response** (server → client):
```json
{"jsonrpc":"2.0","id":1,"result":{"url":"https://example.com","title":"Example Domain"}}
```

**Error** (server → client):
```json
{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}
```

**Notification** (server → client, no `id`):
```json
{"jsonrpc":"2.0","method":"event.console","params":{"tabId":"tab0","level":"log","message":"hello"}}
```

**Framing**: Each message is a single line terminated by `\n`. No length prefix. No HTTP headers.

**Standard JSON-RPC error codes**:
- `-32700` Parse error
- `-32600` Invalid request
- `-32601` Method not found
- `-32602` Invalid params
- `-32603` Internal error
- `-32000` Tab not found (application-defined)
- `-32001` JavaScript error (application-defined)
- `-32002` Navigation error (application-defined)
- `-32003` Timeout (application-defined)

---

## 3. File Structure

All source files live in `aslan-browser/` (the Xcode source group). Files added here auto-sync with the Xcode project via `PBXFileSystemSynchronizedRootGroup`.

```
aslan-browser/                        # Project root
├── aslan-browser.xcodeproj/
├── aslan-browser/                    # Source files (auto-synced)
│   ├── AppDelegate.swift             # NSApplicationDelegate, app lifecycle
│   ├── BrowserTab.swift              # @MainActor: WKWebView + NSWindow + navigation + JS eval
│   ├── TabManager.swift              # Tab lifecycle, tabId → BrowserTab map
│   ├── SocketServer.swift            # SwiftNIO Unix socket listener
│   ├── JSONRPCHandler.swift          # Parse/dispatch JSON-RPC messages
│   ├── MethodRouter.swift            # Maps method names → TabManager/BrowserTab calls
│   ├── ScriptBridge.swift            # Generates WKUserScript JS source (embedded strings)
│   ├── Models/
│   │   ├── RPCMessage.swift          # Codable JSON-RPC request/response/error
│   │   ├── TabInfo.swift             # Tab metadata (id, url, title)
│   │   └── A11yNode.swift            # Accessibility tree node
│   └── Assets.xcassets/
├── aslan-browserTests/
├── aslan-browserUITests/
├── docs/
│   ├── prd.md
│   ├── prompts-are-code.md
│   └── workflows/
│       ├── README.md
│       ├── conventions.md            # This file
│       ├── notes.md
│       ├── phase-{1..6}-*.md
│       └── state/
│           └── phase-{1..6}-plan.json
└── sdk/
    └── python/                       # Phase 6
        ├── pyproject.toml
        └── aslan_browser/
            ├── __init__.py
            ├── client.py
            └── async_client.py
```

**JS code is embedded as Swift string literals** in `ScriptBridge.swift`, not as separate `.js` files. This avoids bundle resource configuration issues and keeps the injection code co-located with its Swift orchestration.

---

## 4. Swift Conventions

### Naming
- **Types**: PascalCase — `BrowserTab`, `SocketServer`, `RPCMessage`
- **Functions/properties**: camelCase — `navigate(to:)`, `evaluateJavaScript(_:)`, `tabId`
- **Constants**: camelCase — `let defaultTimeout = 5000`
- **Files**: Match primary type name — `BrowserTab.swift` contains `class BrowserTab`

### Style
- **One primary type per file.** Small helper types/extensions can coexist if tightly coupled.
- **Minimal comments.** Code should be self-documenting. Comment only non-obvious decisions.
- **No force unwraps** except in `fatalError` paths during app setup.
- **Guard-let for early returns.** Prefer `guard` over nested `if-let`.
- **Trailing closure syntax** for single-closure calls.

### Concurrency
- `BrowserTab` is `@MainActor` — all WKWebView interaction goes through it.
- NIO handlers receive on the event loop, dispatch to `@MainActor` for WebKit calls via `Task { @MainActor in ... }`.
- Image encoding (JPEG compression) happens off-main-thread.
- Each tab's JS evaluations are sequential. Cross-tab parallelism happens at the NIO dispatch level.

### Error Handling
- Define a `BrowserError` enum conforming to `Error` for all domain errors.
- Map `BrowserError` → JSON-RPC error codes in the `JSONRPCHandler`.
- Never silently swallow errors. Always propagate or log.

### Dependencies
- **SwiftNIO** (`swift-nio` 2.x) — Unix socket server. Added via Xcode SPM.
- **Foundation / AppKit / WebKit** — System frameworks. No other external dependencies.
- Do NOT add dependencies without explicit justification. The bar is: "would implementing this ourselves take more than a day AND be less reliable?"

---

## 5. AppKit Patterns

### App Lifecycle
```swift
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start socket server, create default tab
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return false  // Keep running even if windows are hidden
    }
}
```

### Window Creation (per tab)
```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
    styleMask: [.titled, .resizable],
    backing: .buffered,
    defer: false
)
window.contentView = webView

if isHidden {
    window.orderOut(nil)      // Hidden but in window hierarchy
} else {
    window.makeKeyAndOrderFront(nil)  // Visible for debugging
}
```

### Launch Arguments
- `--hidden` — Start with all windows hidden (production mode)
- No flag — Windows visible (development/debug mode)
- Check via `CommandLine.arguments.contains("--hidden")`

---

## 6. WKWebView Patterns

### Configuration (shared across tabs)
```swift
let config = WKWebViewConfiguration()
let userScript = WKUserScript(
    source: ScriptBridge.injectedJS,
    injectionTime: .atDocumentEnd,
    forMainFrameOnly: true
)
config.userContentController.addUserScript(userScript)
config.userContentController.add(messageHandler, name: "agent")
```

### JavaScript Evaluation
Use `callAsyncJavaScript` — it handles Promises automatically and passes arguments safely:
```swift
let result = try await webView.callAsyncJavaScript(
    script,
    arguments: args ?? [:],
    contentWorld: .page
)
```

Use `.page` content world (not `.defaultClient`) so injected scripts can access page globals.

### Navigation
Wrap `WKNavigationDelegate` callbacks in async/await using `CheckedContinuation`:
```swift
func navigate(to url: URL) async throws -> NavigationResult {
    return try await withCheckedThrowingContinuation { continuation in
        self.navigationContinuation = continuation
        webView.load(URLRequest(url: url))
    }
}
```

### Screenshots
```swift
let config = WKSnapshotConfiguration()
config.snapshotWidth = NSNumber(value: width)
let image = try await webView.takeSnapshot(configuration: config)
let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let bitmap = NSBitmapImageRep(cgImage: cgImage)
let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])!
let base64 = jpegData.base64EncodedString()
```

---

## 7. Known Limitations

- **`forMainFrameOnly: true` for WKUserScript**: The injected ScriptBridge only runs in the main frame, not in iframes. This means agent automation won't work inside iframes (common in auth flows, embedded forms, CAPTCHA widgets). If agents hit iframe issues, change to `forMainFrameOnly: false` — but be aware this increases overhead and may cause duplicate event messages from nested frames.

---

## 8. Design Principles

- **KISS**: Simplest solution that works. No premature abstraction.
- **YAGNI**: Don't build it until we need it. Features can be added later.
- **DRY**: Extract shared logic, but not at the cost of readability.
- **Flat over nested**: Prefer flat function calls over deep class hierarchies.
- **Explicit over implicit**: Make data flow visible. No magic.
- **Local over global**: State belongs to the component that uses it.
