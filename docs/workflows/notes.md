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

7. **App Sandbox re-enabled** — Sandbox was disabled in Phase 2 for socket access. Re-enabled with proper entitlements: `network.client`, `network.server`, `files.user-selected.read-write`, `files.downloads.read-write`, and a temporary exception for `/tmp/aslan-browser.sock`. This gives WKWebView's WebContent process proper sandbox permissions, eliminating most pasteboard/launchservices errors.

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

---

## Phase 4 — Accessibility Tree

**Status:** Complete ✅

### Decisions

1. **A11y tree extraction is a single IIFE in ScriptBridge** — All DOM walker code (role inference, name resolution, ref assignment, hidden element filtering) lives in one IIFE block within `ScriptBridge.injectedJS`. Follows the Phase 3 pattern of embedding JS as Swift string literals.

2. **Interaction methods use `callAsyncJavaScript` with argument passing** — Click, fill, select, keypress, and scroll methods pass selectors/values as `callAsyncJavaScript` arguments (not string interpolation) to avoid injection attacks.

3. **Target resolution in Swift, not JS** — The `resolveSelector()` helper in BrowserTab converts `@eN` refs to `[data-agent-ref="@eN"]` CSS selectors before passing to JS. Keeps JS simple.

### Discoveries

1. **Regex in Swift multiline strings needs double-backslash** — JS regex like `/\s+/` must be written as `/\\s+/` inside Swift multiline string literals (`"""`). `\s` is not a valid Swift escape sequence.

2. **`TreeWalker` for DOM traversal** — Used `document.createTreeWalker` instead of recursive descent for efficient DOM walking. Only visits ELEMENT_NODE types.

3. **Refs are ephemeral** — `extractA11yTree()` removes all previous `data-agent-ref` attributes before assigning new sequential refs starting from `@e0`. This means refs from a previous extraction are invalid after a new one.

4. **Hidden element detection covers 4 cases** — `aria-hidden="true"`, `display:none`, `visibility:hidden`, and zero-size bounding rect (width === 0 && height === 0).

5. **`getValue()` returns `undefined` for non-input elements** — Only INPUT, TEXTAREA, and SELECT elements include `value` in the tree node. Other elements omit the field entirely (not `null`).

### Architecture

`extractA11yTree()` flow:
1. Remove all existing `data-agent-ref` attributes
2. TreeWalker traversal over `document.body`
3. For each element: `shouldInclude()` → `!isHidden()` → `getRole()` → assign ref → `resolveName()` → `getValue()` → `getRect()`
4. Returns flat array of node objects

Interaction methods: `click`, `fill`, `select`, `keypress`, `scroll` — all resolve targets via `@eN` refs or CSS selectors.

JSON-RPC methods added: `getAccessibilityTree`, `click`, `fill`, `select`, `keypress`, `scroll`

### Files Added
- `aslan-browser/Models/A11yNode.swift` — Codable structs for A11yNode and A11yRect

### Files Modified
- `aslan-browser/ScriptBridge.swift` — Added `extractA11yTree()` with role inference, name resolution, ref assignment, hidden element filtering
- `aslan-browser/BrowserTab.swift` — Added `getAccessibilityTree()`, `click()`, `fill()`, `select()`, `keypress()`, `scroll()`, `resolveSelector()` 
- `aslan-browser/MethodRouter.swift` — Wired 6 new JSON-RPC methods

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

---

## Phase 5 — Tab Management + Events

**Status:** Complete ✅

### Decisions

1. **TabManager is @MainActor** — Manages the tabId → BrowserTab map. Tab IDs are auto-generated: "tab0", "tab1", etc. Default tab0 created on app launch synchronously (before socket server starts).

2. **tabId defaults to "tab0"** — All existing JSON-RPC methods accept optional `tabId` param. If not provided, defaults to "tab0" for backward compatibility.

3. **Event chain: BrowserTab → TabManager → SocketServer** — BrowserTab has `onEvent` closure, TabManager forwards via `broadcastEvent` closure, AppDelegate connects to `SocketServer.broadcast`. No direct coupling between layers.

4. **SocketServer tracks channels with NSLock** — Client channels stored in `[ObjectIdentifier: Channel]` dict protected by NSLock. Safe for cross-thread access (MainActor → NIO event loop).

5. **App Sandbox disabled** — Set `ENABLE_APP_SANDBOX = NO` and removed sandbox entitlements. The temporary-exception for `/tmp/aslan-browser.sock` was not being properly embedded in codesigned binary. Sandbox disabled is acceptable for local dev/agent tool.

### Discoveries

1. **NSWindow close animation causes use-after-free** — Closing a tab's NSWindow triggers `_NSWindowTransformAnimation` objects that reference the window. When ARC releases the BrowserTab (removed from TabManager dict), the animation objects become dangling pointers. Crash in `objc_release` during autorelease pool drain.

2. **Fix: deferred cleanup for tab close** — `closeTab` sets `animationBehavior = .none`, calls `orderOut(nil)`, and keeps the BrowserTab in a `closingTabs` array for 500ms. BrowserTab's `cleanup()` method disconnects all delegates, message handlers, and stops loading before the window is hidden.

3. **Cookie domain matching** — `HTTPCookie.domain` with leading dot (e.g., `.example.com`) needs special handling. Strip the dot and match: host == strippedDomain OR host.hasSuffix("." + strippedDomain).

4. **Console capture via JS override** — Override `console.log/warn/error/info` in ScriptBridge to post messages to Swift. Original methods still called after posting. Also capture `window.onerror` and `unhandledrejection` events.

5. **Event notifications skip by id** — JSON-RPC notifications (no `id` field) can interleave with responses. Client test code must skip lines without `id` when waiting for a specific response.

### Architecture

Full API surface complete:
- **Tab management**: tab.create, tab.close, tab.list
- **Navigation**: navigate (with waitUntil), goBack, goForward, reload, waitForSelector
- **Interaction**: click, fill, select, keypress, scroll
- **Extraction**: getAccessibilityTree, getHTML (via evaluate), getTitle, getURL, screenshot
- **State**: getCookies, setCookie
- **Events**: event.console, event.navigation, event.error notifications

### Files Added
- `aslan-browser/TabManager.swift` — Tab lifecycle management
- `aslan-browser/Models/TabInfo.swift` — Tab metadata struct

### Files Modified
- `aslan-browser/AppDelegate.swift` — Uses TabManager, connects event broadcasting
- `aslan-browser/BrowserTab.swift` — Added tabId, onEvent, cleanup(), getCookies, setCookie, goBack, goForward, reload, configurable width/height
- `aslan-browser/MethodRouter.swift` — All methods resolve tabId from params. Added tab.create/close/list, getCookies, setCookie, goBack, goForward, reload
- `aslan-browser/ScriptBridge.swift` — Console capture, JS error capture
- `aslan-browser/SocketServer.swift` — Client channel tracking, broadcast method
- `aslan-browser/JSONRPCHandler.swift` — Channel registration/unregistration with SocketServer
- `aslan-browser/aslan_browser.entitlements` — Removed sandbox, kept network entitlements
- `tests/test_socket.py` — 19 tests covering full API surface

Phase 5 complete. Full API surface operational. Ready for Python SDK.

---

## Phase 6 — Python SDK + Polish

**Status:** Complete ✅

### Architecture

- **Sync client** (`client.py`): `AslanBrowser` class using stdlib `socket` + `json`. Connects to Unix socket, sends NDJSON JSON-RPC, reads responses line-by-line skipping event notifications.
- **Async client** (`async_client.py`): `AsyncAslanBrowser` using `asyncio.open_unix_connection`. Background read loop routes responses by request ID and dispatches notifications to optional event callback.
- **Zero external dependencies**. Only Python stdlib.
- **Context managers**: `with AslanBrowser()` / `async with AsyncAslanBrowser()`.
- **Connection retry**: 3 attempts with 100ms/500ms/1000ms backoff.
- **Screenshots return `bytes`**: Base64 decoding happens in the SDK.
- **`AslanBrowserError(code, message)`** raised for all JSON-RPC errors.

### Benchmark Results

| Benchmark | Median | Target |
|---|---|---|
| JS eval round-trip | 0.13ms | <2ms ✓ |
| Screenshot (1440w) | 2.47ms | <30ms ✓ |
| Screenshot (800w) | 0.95ms | — |
| A11y tree (simple) | 0.17ms | <50ms ✓ |
| A11y tree (complex) | 2.73ms | <50ms ✓ |

### Discoveries

1. **pytest-asyncio strict mode requires `@pytest_asyncio.fixture`** — Async fixtures decorated with plain `@pytest.fixture` are passed as raw async generators. Must use `@pytest_asyncio.fixture` or set `asyncio_mode = "auto"` in pyproject.toml.

2. **Each sync test gets a fresh socket connection** — Tests that share tab0 can interfere if a prior test's navigation is still in-flight when the new connection navigates. Fresh connections per test fixture avoid this.

Phase 6 complete. All 6 phases done. aslan-browser is fully operational.

---

## Real-World Testing & Agent Integration (2026-02-19)

**Status:** Validated ✅

### User-Agent Fix (Critical)

1. **WKWebView's default UA gets flagged by Google/Gmail** — Default UA string looks like `AppleWebKit/605.1.15 ... Safari/605.1.15`, which Google classifies as an unsupported embedded browser. Gmail shows a "This browser version is no longer supported" banner.

2. **Fix: Set `customUserAgent` to Chrome UA** — Added `wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"` in `BrowserTab.init`. One line. Eliminates the banner entirely.

3. **This should be the default for any agent browser** — Sites like Google, LinkedIn, and Facebook actively check UA strings. A modern Chrome UA is required for full compatibility.

### Real-World Site Validation

Successfully tested full interactive flows on:
- **Gmail** — Login (email + password + 2FA), inbox navigation, reading accessibility tree (524 nodes)
- **LinkedIn** — Login, feed browsing, notification checking, full page interaction
- **Facebook** — Login, switching to business page (Uzunu), creating post draft with text + image upload
- **Hacker News** — Story listing, comment reading, article navigation
- **Amazon** — Product page rendering, complex DOM extraction

All sites worked with the Chrome UA. Sessions persist across browser restarts (cookies retained).

### Tree-First Agent Pattern (Key Learning)

The most important operational insight: **the accessibility tree should be the primary interface for AI agents, not screenshots.**

| Metric | A11y Tree | Screenshot |
|---|---|---|
| Latency | ~5ms | ~13ms |
| Payload | ~22-33KB JSON | ~150-250KB JPEG |
| LLM tokens | Low (structured text) | Very high (vision) |
| Actionable | Yes (@eN refs) | No (pixels only) |

**LinkedIn benchmark: 30x fewer tokens with a11y tree vs raw DOM.**

**Rule: Use tree for everything. Screenshot only for:**
- Visual verification (did the image upload? does it look right?)
- Showing results to the user
- When tree is ambiguous or page relies on visual layout

A Facebook post draft flow (navigate → find button → click → type text → attach image → verify) took **4 tree-based commands and only 1 screenshot** at the end.

### Contenteditable / Rich Text Fields

Facebook's post composer uses `contenteditable` divs, not `<input>` or `<textarea>`. The SDK's `fill()` method (which sets `.value`) doesn't work on these.

**Workaround:** Use `document.execCommand("insertText", false, text)` via `evaluate()`:
```python
browser.evaluate('''
    var editors = document.querySelectorAll("[contenteditable=true]");
    for (var e of editors) {
        if (e.closest("[role=dialog]")) {
            e.focus();
            document.execCommand("insertText", false, text);
            return "done";
        }
    }
''', args={'text': post_text})
```

**TODO:** Consider adding a `fill_rich()` or `type_text()` method to the SDK that handles contenteditable automatically.

### File Upload Without Native Picker

WKWebView file input clicks open a native macOS file picker that can't be automated via JS. However, files can be set programmatically using the `DataTransfer` API:

```python
# Read file, base64 encode, inject via DataTransfer
browser.evaluate('''
    var input = document.querySelector("input[type=file]");
    var binary = atob(b64data);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    var file = new File([bytes], filename, { type: mimetype });
    var dt = new DataTransfer();
    dt.items.add(file);
    input.files = dt.files;
    input.dispatchEvent(new Event("change", { bubbles: true }));
''', args={'b64data': img_b64, 'filename': 'photo.png', 'mimetype': 'image/png'})
```

This successfully uploaded images to Facebook. Works for any site that uses standard file inputs.

**TODO:** Consider adding an `upload()` method to the SDK that wraps this pattern.

### System-Wide Installation

Installed from source:
- **App:** `/Applications/aslan-browser.app` (Release build)
- **CLI:** `~/.local/bin/aslan-browser` (shell wrapper)
- **Python SDK:** `pip install -e sdk/python/`

### Helper Tool: `ab.py`

Created `ab.py` — a quick CLI for interactive agent control:
```bash
python3 ab.py nav "https://example.com"   # navigate
python3 ab.py tree                          # print a11y tree
python3 ab.py click "@e5"                   # click by ref
python3 ab.py fill "@e3" "hello"            # fill input
python3 ab.py shot /tmp/page.jpg            # screenshot
python3 ab.py eval "return document.title"  # JS eval
python3 ab.py back                          # go back
python3 ab.py key Escape                    # keypress
```

Useful for interactive agent sessions where an LLM drives the browser step-by-step.

---

## Phase 7 — Usability & Multi-Agent

**Status:** Complete ✅

### Changes
- Edit menu added (Cmd+C/V/X/A/Z now work in WKWebView fields)
- Window controls: close, minimize, window titles showing tab + page info
- Address bar for manual URL entry with auto https:// prepend
- Session-based tab ownership for multi-agent isolation
- Batch JSON-RPC method for parallel operations
- Python SDK: session_create, session_destroy, batch, parallel_get_trees, parallel_navigate, parallel_screenshots

### Decisions

1. **Edit menu uses `Selector(("undo:"))` for undo/redo** — These Objective-C selectors aren't exposed as `#selector` targets in Swift. Double-parenthesis syntax is required. `cut:`, `copy:`, `paste:`, `selectAll:` use `#selector(NSText.*)`.

2. **`windowShouldClose` returns `false`** — TabManager handles actual close via `closeTab()` flow to avoid the use-after-free crash discovered in Phase 5. The `onWindowClose` callback bridges from NSWindowDelegate to TabManager.

3. **URL bar container uses default `translatesAutoresizingMaskIntoConstraints = true`** — NSWindow manages contentView sizing, so the container view keeps the default. Only subviews (urlField, webView) use Auto Layout with `translatesAutoresizingMaskIntoConstraints = false`.

4. **Sessions are NOT tied to socket connections** — A session persists until explicitly destroyed. Multiple connections can share a session if they know the sessionId. This allows agent reconnection.

5. **Batch rejects nested batch** — If a sub-request method is `"batch"`, it returns an error for that sub-request to prevent recursion.

6. **Default tab0 has no session** — It belongs to everyone (backward-compatible). Only tabs created with explicit `sessionId` are session-scoped.

### Architecture

New JSON-RPC methods: `session.create`, `session.destroy`, `batch`
Modified methods: `tab.create` (accepts `sessionId`), `tab.list` (accepts `sessionId` filter)
New RPC error code: `-32004` (session not found)

---

## Phase 7 — Live Manual Test (2026-02-19)

**Test:** Open Google, search "dentists in Arroyo Grande", open results in tabs using Phase 7 features.

### Gotcha 1: `/Applications/` binary was stale — always launch from DerivedData after a phase

The app in `/Applications/aslan-browser.app` was the pre-Phase-7 build. `session.create` and `batch` didn't exist on it. The Phase 7 binary lives at:

```
~/Library/Developer/Xcode/DerivedData/aslan-browser-*/Build/Products/Debug/aslan-browser.app
```

**Workflow for live testing after a build:**
```bash
pkill -x "aslan-browser"
open "$DERIVED_DATA/Build/Products/Debug/aslan-browser.app"
```

Verify you're on the right binary by probing a Phase 7-only method immediately:
```bash
echo '{"jsonrpc":"2.0","id":1,"method":"session.create","params":{}}' | nc -U /tmp/aslan-browser.sock
```
If it returns `methodNotFound`, you're on the old binary.

**TODO:** The Release install step at end of each phase workflow should be enforced — copy to `/Applications/` so the installed version is never stale.

---

### Gotcha 2: `event.navigation` notifications interleave before RPC responses

When `navigate` is called, the socket can emit an `event.navigation` notification *before* returning the actual JSON-RPC response. A naive reader that grabs the first line will return the notification, not the result.

**Fix:** Read lines in a loop and match by `id` field. Skip any object without the expected `id`:

```python
def rpc(method, params=None, req_id=1):
    ...
    for line in lines:
        obj = json.loads(line)
        if obj.get('id') == req_id:   # ← match by id, skip events
            return obj
```

This was documented in Phase 5 notes but easy to forget when writing quick one-off test scripts.

---

### Gotcha 3: Multi-line JS in batch requests gets mangled — use heredocs or single-line scripts

Embedding multi-line JavaScript inside a Python f-string and sending it through JSON causes escape sequences to break. A complex JS block with `\n`, backslashes, and embedded quotes will produce `-32001 JavaScript error` silently.

**Broken pattern:**
```python
js = '''
var clone = body.cloneNode(true);
clone.querySelectorAll('script').forEach(el => el.remove());
return clone.innerText.replace(/[ \t]+/g, ' ');
'''
requests = [{'method': 'evaluate', 'params': {'script': js}}]
```

**Working patterns:**

Option A — single-line script (preferred for batch):
```python
script = "return document.body.innerText.replace(/[ \\t]+/g,' ').substring(0,4000)"
```

Option B — Python heredoc with `<< 'PYEOF'` for the whole script, avoiding any f-string interpolation:
```bash
python3 << 'PYEOF'
js = "return document.body.innerText.substring(0,3000)"
PYEOF
```

**Rule:** Keep `evaluate` scripts single-line when embedding in batch requests. Reserve multi-line scripts for standalone `evaluate` calls where escaping is easier to control.

---

### Gotcha 4: ATS blocks `http://` URLs — always retry with `https://`

macOS App Transport Security (ATS) is enforced even with sandbox disabled. Any URL with a plain `http://` scheme returns:

```
Navigation error: The resource could not be loaded because the App Transport Security
policy requires the use of a secure connection.
```

Google's local pack sometimes surfaces dental practice sites that are still on HTTP (small local businesses). Two of the five result tabs failed for this reason.

**Fix:** Before navigating, normalize URLs:
```python
if url.startswith('http://'):
    url = 'https://' + url[7:]
```

Or handle the `-32002` error and retry with `https://`. Both work. The retry approach is more accurate because some `http://` sites don't have a working HTTPS version.

**TODO:** Consider adding automatic HTTP→HTTPS upgrade in `BrowserTab.navigate()` before issuing the request, with a fallback to the original `http://` if `https://` fails.

---

### Gotcha 5: Google `#:~:text=` fragment links create duplicate tabs

Google search results include "Read more" links that use text fragment anchors: `https://example.com/#:~:text=some+snippet`. These point to the same page as the canonical result link but with a fragment. Scraping all `<a href>` tags from the SERP without deduplication produces pairs like:

- `https://perrypateldds.com/`  ← canonical
- `https://perrypateldds.com/#:~:text=Conveniently+located...` ← duplicate

**Fix:** Deduplicate by stripping fragments before comparing:
```python
# In the JS scraper
if (href.includes('#:~:text=')) continue;  // skip text fragments entirely
```

Or in Python:
```python
from urllib.parse import urldefrag
canonical, _ = urldefrag(url)
```

---

### Learning: `batch` + `session` is the right pattern for multi-tab research

The full dentist search flow demonstrated the Phase 7 design working end-to-end:

1. `session.create` → isolates all result tabs under one session ID
2. `tab.create` × N with `sessionId` → tabs tagged to session
3. `batch` navigate → all N tabs loaded in **one socket round-trip**
4. `batch` evaluate → all N pages read in **one socket round-trip**
5. `tab.list(sessionId)` → confirms only the right tabs are in scope

Total socket calls for opening + reading 6 dentist pages: **5 calls** (create session, scrape Google, create 6 tabs, batch navigate, batch read). Without batch that would be 14+ sequential calls.

---

## Phase 8 — Loading Feedback

**Status:** Complete ✅

### Changes
- Loading state tracking via `isLoading` property and WKNavigationDelegate hooks
- Firefox-style status bar at bottom of window (appears during loading, shows URL)
- Go/Stop button next to URL field ("→" idle, "✕" loading)
- URL field text grays out during loading (`.tertiaryLabelColor`)
- API-initiated navigation (JSON-RPC) also triggers all visual feedback immediately

### Implementation Details

1. **Status bar uses toggling height constraint** — Instead of just `isHidden`, the status bar height constraint toggles between 0 and 20. This ensures the WKWebView reclaims the 20px when the status bar is hidden, since Auto Layout still reserves space for hidden views with active constraints.

2. **Go button wired after `super.init()`** — Same pattern as the URL field. Button is created before `super.init()` with nil target/action, then `target = self` and `action = #selector(goButtonAction(_:))` are set after.

3. **`didStartProvisionalNavigation` is nonisolated** — Matches the pattern of existing WKNavigationDelegate methods. Dispatches to MainActor via `Task { @MainActor in }`.

4. **Loading state set in `navigate()` before `webView.load()`** — For API-initiated navigation, `isLoading` is set to true and `updateLoadingUI()` called before the switch/load block. This ensures the UI updates immediately without waiting for the `didStartProvisionalNavigation` delegate callback.

5. **Loading UI is separate from readiness tracking** — `isLoading` is purely for visual feedback. The readiness system (`didFinishNavigation`, `domStable`, `networkIdle`, `readyStateComplete`) remains unchanged and is used by `waitForIdle`.

### Files Modified
- `aslan-browser/BrowserTab.swift` — All changes in this single file

---

## Phase 9 — CLI

**Status:** Complete ✅

### Changes
- Added `aslan` CLI tool (sdk/python/aslan_browser/cli.py, ~630 lines)
- Entry point via pyproject.toml [project.scripts]
- State file at /tmp/aslan-cli.json tracks current tab
- 28 commands: status, source, nav, back, forward, reload, tree, title, url, text, html, eval, click, fill, type, select, key, scroll, wait, upload, shot, tabs, tab:new, tab:close, tab:use, tab:wait, cookies, set-cookie
- CLI_REFERENCE.md — agent-facing cheat sheet (~190 lines)
- Rewrote SKILL.md to teach CLI instead of Python SDK (~108 lines, down from ~300+)
- Updated knowledge/core.md for CLI-specific gotchas
- Integration tests in tests/test_cli.py (18 tests)

### Token Impact
- Per-interaction: ~200 tokens → ~30 tokens (85% reduction)
- Skill context: ~5,000 tokens → ~2,600 tokens (~48% reduction)

### Design Decisions
1. **`auto_session=False` for CLI** — CLI is stateless per call. No session creation/teardown overhead. State tracked via `/tmp/aslan-cli.json` (current tab only).
2. **Tab not found auto-recovery** — if current tab doesn't exist, reset to tab0 and retry once.
3. **Compact output by default** — tree prints one line per node, nav prints title+URL. `--json` flag for programmatic access.
4. **Zero new dependencies** — pure Python, wraps existing AslanBrowser SDK client.
5. **`aslan upload` added after initial implementation** — file upload via DataTransfer API was the one operation that still required Python SDK boilerplate (base64 string too large for shell arg). Now fully CLI: `aslan upload /path/to/file.jpg`. Generic — works on any site with `input[type=file]`.
6. **`aslan type` — universal text input** — auto-detects contenteditable vs input/textarea. Uses `execCommand("insertText")` for contenteditable, `.value` + input/change events for regular inputs. Eliminates the #1 eval workaround across LinkedIn, Facebook, Instagram, Notion.
7. **`aslan html` — page HTML** — like `text` but returns innerHTML. Supports `--selector` to target specific elements. Eliminates the `aslan eval "return document.body.innerHTML..."` pattern.
8. **`aslan wait --idle/--load`** — wait for page readiness after click-triggered navigation. Polls `__agent._networkIdle` and `__agent._domStable` (idle) or `document.readyState` (load). Eliminates unreliable `sleep` calls.
