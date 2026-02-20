# AgentBrowser — Native macOS Browser for AI Agents

> **One-liner:** A Swift/AppKit app wrapping WKWebView, exposing a JSON-RPC API over a Unix socket so AI agents can browse the web 2–5× faster than Puppeteer/CDP.

---

## 1 · Goals & Non-Goals

### Goals
- Sub-2ms JS evaluation round-trips (vs 2–5ms CDP)
- Sub-30ms screenshots as raw JPEG bytes (vs 50–150ms CDP base64-in-JSON)
- Deterministic navigation: every `navigate` call resolves only when page is *truly* ready (DOM stable + network idle)
- Accessibility-tree-first page representation for token-efficient LLM consumption
- Single binary, zero external dependencies, macOS-only

### Non-Goals
- Cross-platform support
- HTTP/HTTPS request/response body interception (WKWebView limitation — accept it)
- Browser extension support
- Acting as a general-purpose user-facing browser
- Replicating full CDP feature surface

---

## 2 · Architecture

```
┌──────────────────────────────────────────────────┐
│  AI Agent (Python/Node/any language)             │
│  Connects to: /tmp/agentbrowser.sock             │
└──────────────┬───────────────────────────────────┘
               │ JSON-RPC 2.0 over Unix Socket
               │ + raw binary for screenshots
┌──────────────▼───────────────────────────────────┐
│  AgentBrowser Process (Swift, AppKit)            │
│                                                  │
│  ┌─────────────┐  ┌──────────────────────────┐   │
│  │ SocketServer │  │ TabManager               │   │
│  │ (SwiftNIO)  │──│  tab0: BrowserTab        │   │
│  │             │  │  tab1: BrowserTab        │   │
│  │ JSON-RPC    │  │  ...                     │   │
│  │ dispatcher  │  └──────────────────────────┘   │
│  └─────────────┘           │                     │
│                    ┌───────▼──────────┐           │
│                    │ BrowserTab       │           │
│                    │  - WKWebView     │           │
│                    │  - NSWindow      │           │
│                    │    (hidden)      │           │
│                    │  - NavDelegate   │           │
│                    │  - ScriptBridge  │           │
│                    └──────────────────┘           │
└──────────────────────────────────────────────────┘
```

### Key design decisions

| Decision | Choice | Why |
|---|---|---|
| UI framework | **AppKit** | Full NSWindow control; WKWebView needs window hierarchy to avoid JS throttling; SwiftUI has documented lifecycle bugs for this use case |
| Server | **SwiftNIO + Unix socket** | ~30% faster than TCP for small msgs; no port conflicts; filesystem permissions = security |
| Protocol | **JSON-RPC 2.0** | Language-agnostic, simple, well-tooled; one exception: screenshot endpoint returns raw bytes |
| Concurrency | **Swift async/await** | BrowserTab is `@MainActor`; NIO handlers dispatch to MainActor for WKWebView calls; image encoding on background threads |
| Window strategy | **Hidden NSWindow per tab** | `window.orderOut(nil)` — invisible but in hierarchy so JS/WebSockets work normally |

---

## 3 · Core Components

### 3.1 `BrowserTab` — `@MainActor` class

Owns one `WKWebView` + one hidden `NSWindow`. All WebKit interaction funnels through here.

**WKWebView configuration:**
- Shared `WKWebViewConfiguration` with:
  - `WKUserScript` injected at `.atDocumentEnd` (the automation bridge — see §4)
  - `WKScriptMessageHandler` registered on channel `"agent"` for page→Swift events
  - `WKContentWorld.defaultClient` isolation for all injected scripts
  - `WKWebpagePreferences.allowsContentJavaScript = true`
- `WKNavigationDelegate` for lifecycle hooks
- `WKUIDelegate` for alert/confirm/prompt interception (auto-dismiss or forward to agent)

**Deterministic readiness detection:**
Navigation resolves when ALL conditions met:
1. `WKNavigationDelegate.didFinish` fired
2. Injected MutationObserver reports no DOM changes for 500ms
3. Injected fetch/XHR monkey-patch reports zero pending requests
4. `document.readyState === "complete"`

Expose as `waitUntil` param: `"load"` (just didFinish), `"idle"` (all 4), `"none"` (return immediately).

### 3.2 `SocketServer` — SwiftNIO

Listens on `/tmp/agentbrowser.sock`. Handles:
- **JSON-RPC requests** → dispatches to TabManager → returns JSON-RPC response
- **`GET /screenshot`** → returns raw JPEG bytes with `Content-Type: image/jpeg`
- **`GET /events`** → SSE stream for push events (navigation, console, errors)

### 3.3 `TabManager`

Manages tab lifecycle. Maps `tabId: String → BrowserTab`. Default tab created on launch.

### 3.4 `ScriptBridge` — injected JS

A `WKUserScript` injected into every page providing:
- `window.__agent.waitForSelector(sel, timeoutMs)`
- `window.__agent.extractA11yTree()` → returns accessibility tree
- `window.__agent.getReadyState()` → returns readiness signals
- Monkey-patched `fetch`/`XMLHttpRequest` to track pending requests
- `MutationObserver` watching `document.body` for DOM stability

All page→Swift communication via `window.webkit.messageHandlers.agent.postMessage(...)`.

---

## 4 · API Surface (JSON-RPC Methods)

### Tab management

| Method | Params | Returns | Notes |
|---|---|---|---|
| `tab.create` | `{url?, width?, height?}` | `{tabId}` | Defaults 1440×900 |
| `tab.close` | `{tabId}` | `{ok}` | |
| `tab.list` | — | `{tabs: [{tabId, url, title}]}` | |

### Navigation

| Method | Params | Returns | Notes |
|---|---|---|---|
| `navigate` | `{tabId, url, waitUntil?}` | `{url, title, status}` | waitUntil: `"load"` \| `"idle"` \| `"none"` |
| `goBack` | `{tabId}` | `{url, title}` | |
| `goForward` | `{tabId}` | `{url, title}` | |
| `reload` | `{tabId}` | `{url, title}` | |
| `waitForSelector` | `{tabId, selector, timeout?}` | `{found: bool}` | Uses injected MutationObserver |

### Page interaction

| Method | Params | Returns | Notes |
|---|---|---|---|
| `evaluate` | `{tabId, script, args?}` | `{result}` | Uses `callAsyncJavaScript`; args passed safely as dict; awaits Promises |
| `click` | `{tabId, selector}` | `{ok}` | querySelector → focus → click via JS |
| `fill` | `{tabId, selector, value}` | `{ok}` | Sets .value + dispatches input/change events |
| `select` | `{tabId, selector, value}` | `{ok}` | For `<select>` elements |
| `keypress` | `{tabId, key, modifiers?}` | `{ok}` | Dispatches KeyboardEvent |
| `scroll` | `{tabId, x, y}` | `{ok}` | window.scrollTo or element.scrollIntoView |

### Page state extraction

| Method | Params | Returns | Notes |
|---|---|---|---|
| `screenshot` | `{tabId, quality?, width?}` | **raw JPEG bytes** | NOT JSON — binary response. quality 0–100, default 70 |
| `getAccessibilityTree` | `{tabId}` | `{tree: [{ref, role, name, value, rect}]}` | The primary page representation for agents |
| `getHTML` | `{tabId, selector?}` | `{html}` | outerHTML of selector or full document |
| `getTitle` | `{tabId}` | `{title}` | |
| `getURL` | `{tabId}` | `{url}` | |
| `getCookies` | `{tabId, url?}` | `{cookies: [...]}` | Via WKHTTPCookieStore |
| `setCookie` | `{tabId, cookie}` | `{ok}` | Wait for completion before navigating |

### Events (SSE stream on `/events?tabId=X`)

| Event | Data |
|---|---|
| `navigation` | `{url, status}` |
| `console` | `{level, message}` |
| `error` | `{message, source, line}` |
| `download` | `{url, suggestedFilename}` |

---

## 5 · Accessibility Tree Extraction (Critical for Agent Use)

This is the **highest-value feature** — the thing that makes this worth building over just using Playwright.

The injected JS (`__agent.extractA11yTree()`) walks the DOM and returns a flat array of interactive/semantic elements:

```json
[
  {"ref": "@e0", "role": "link", "name": "Sign In", "tag": "A", "rect": {"x":10,"y":50,"w":80,"h":24}},
  {"ref": "@e1", "role": "textbox", "name": "Email", "tag": "INPUT", "value": "", "rect": {...}},
  {"ref": "@e2", "role": "textbox", "name": "Password", "tag": "INPUT", "value": "", "rect": {...}},
  {"ref": "@e3", "role": "button", "name": "Log In", "tag": "BUTTON", "rect": {...}}
]
```

**Rules for extraction:**
- Assign stable `ref` IDs (`@e0`, `@e1`, ...) — persist within page state, reset on navigation
- Tag each element with `data-agent-ref` attribute so `click`/`fill` can resolve by ref
- Include: all interactive elements (links, buttons, inputs, selects, textareas), all ARIA landmarks, all elements with `role` attribute
- Exclude: hidden elements (`display:none`, `visibility:hidden`, `aria-hidden="true"`), elements with zero bounding rect
- `name` resolution order: `aria-label` → `aria-labelledby` target text → `<label>` text → `placeholder` → `title` → visible `textContent` (truncated to 80 chars)
- `role` resolution: explicit `role` attr → implicit role from tag (INPUT→textbox, A→link, BUTTON→button, etc.)
- Include `value` for inputs/selects/textareas
- Include bounding `rect` for spatial reasoning / click targeting

**This tree replaces raw DOM for LLM consumption — 10–100× fewer tokens for equivalent information.**

Agent workflow: `getAccessibilityTree` → LLM picks `@e1` → `fill(@e1, "user@mail.com")` → `click(@e3)`.

---

## 6 · Implementation Plan

### Phase 1 — Skeleton (Day 1–2)
- [ ] Swift Package with AppKit app lifecycle (`@main` + `NSApplicationDelegate`)
- [ ] `BrowserTab` class: creates hidden NSWindow + WKWebView
- [ ] Basic `navigate(url)` with async/await wrapping `WKNavigationDelegate`
- [ ] `evaluate(script)` wrapping `callAsyncJavaScript`
- [ ] `screenshot()` via `takeSnapshot` → JPEG encoding
- [ ] Manual testing: hardcode a URL, navigate, take screenshot, save to disk

### Phase 2 — Socket Server (Day 3–4)
- [ ] SwiftNIO Unix socket listener
- [ ] JSON-RPC 2.0 request parser + response builder
- [ ] Method dispatcher routing to TabManager → BrowserTab
- [ ] Binary screenshot endpoint (separate from JSON-RPC)
- [ ] Basic error handling: invalid method, tab not found, JS errors
- [ ] Test with `socat` or a simple Python client

### Phase 3 — ScriptBridge + Readiness (Day 5–6)
- [ ] WKUserScript injection at document end
- [ ] `waitForSelector` with MutationObserver
- [ ] Fetch/XHR monkey-patching for pending request tracking
- [ ] Combined readiness detection (DOM stable + network idle + readyState)
- [ ] `waitUntil: "idle"` integration into `navigate`

### Phase 4 — Accessibility Tree (Day 7–8)
- [ ] DOM walker JS: role inference, name resolution, rect extraction
- [ ] `data-agent-ref` tagging
- [ ] `getAccessibilityTree` method
- [ ] `click`/`fill`/`select` methods that accept `@eN` refs OR CSS selectors
- [ ] Test on complex pages (Gmail, GitHub, Amazon)

### Phase 5 — Tab Management + Events (Day 9–10)
- [ ] Multi-tab support: `tab.create`, `tab.close`, `tab.list`
- [ ] SSE event stream: navigation, console, errors
- [ ] Cookie get/set with race condition handling
- [ ] `goBack`/`goForward`/`reload`

### Phase 6 — Python SDK + Polish (Day 11–14)
- [ ] Thin Python client library (sync + async) connecting over Unix socket
- [ ] `pip install agentbrowser`
- [ ] Retry logic, connection management, graceful shutdown
- [ ] README with quickstart
- [ ] Performance benchmarks vs Puppeteer on: navigation, screenshot, JS eval, a11y tree extraction

---

## 7 · File Structure

```
AgentBrowser/
├── Package.swift                     # SwiftPM manifest
├── Sources/
│   └── AgentBrowser/
│       ├── main.swift                # @main, NSApplication setup
│       ├── AppDelegate.swift         # NSApplicationDelegate, starts SocketServer + default tab
│       ├── BrowserTab.swift          # @MainActor: WKWebView + NSWindow + navigation + JS eval
│       ├── TabManager.swift          # Tab lifecycle, tabId → BrowserTab map
│       ├── SocketServer.swift        # SwiftNIO Unix socket listener
│       ├── JSONRPCHandler.swift      # Parse/dispatch JSON-RPC, route to methods
│       ├── MethodRouter.swift        # Maps method names → BrowserTab calls
│       ├── ScriptBridge.swift        # Generates WKUserScript source (the injected JS)
│       ├── AccessibilityExtractor.js # JS source for a11y tree extraction (embedded as string)
│       ├── ReadinessDetector.js      # JS source for DOM/network idle detection
│       └── Models/
│           ├── RPCRequest.swift      # Codable JSON-RPC request
│           ├── RPCResponse.swift     # Codable JSON-RPC response
│           ├── TabInfo.swift         # Tab metadata
│           └── A11yNode.swift        # Accessibility tree node
└── sdk/
    └── python/
        ├── agentbrowser/
        │   ├── __init__.py
        │   ├── client.py             # Sync client
        │   └── async_client.py       # Async client
        └── pyproject.toml
```

---

## 8 · Dependencies

| Dependency | Version | Purpose |
|---|---|---|
| swift-nio | 2.x | Unix socket server |
| swift-nio-extras | 1.x | Byte buffer utilities |
| Foundation/AppKit/WebKit | System | Everything else |

That's it. Two external packages.

---

## 9 · Key Technical Constraints

| Constraint | Impact | Mitigation |
|---|---|---|
| **No HTTP/S request interception** | Can't inspect/modify network requests | Monkey-patch fetch/XHR in JS for URL-level visibility; accept this limitation |
| **Main thread only for WKWebView** | All WebKit calls serialize through MainActor | Batch JS evaluations; encode images on background threads; keep main thread ops minimal |
| **WKWebView needs window hierarchy** | Can't run truly headless | Hidden NSWindow with `orderOut(nil)` — invisible but functional |
| **`evaluateJavaScript` must be main thread** | Can't parallelize JS evals across tabs | Each tab's eval is sequential; cross-tab parallelism happens at NIO dispatch level |
| **Cookie race conditions** | `setCookie` completion must be awaited | Always await cookie operations before navigating; document this in SDK |
| **ITP enabled by default** | Third-party cookies blocked | Document; optionally disable via `WKWebsiteDataStore` configuration |
| **No headless screenshot without window** | Must have window for `takeSnapshot` | Hidden window approach handles this |

---

## 10 · Success Metrics

| Metric | Target | How to measure |
|---|---|---|
| JS eval round-trip | < 2ms p95 | Benchmark loop: 1000 `evaluate("1+1")` calls |
| Screenshot latency | < 30ms p95 | Time from `screenshot` call to JPEG bytes available |
| Navigation + idle | < network time + 600ms | Compare `navigate(waitUntil:"idle")` vs raw curl |
| A11y tree extraction | < 50ms on complex pages | Benchmark on Gmail inbox, GitHub repo page |
| Memory per tab | < 80MB | Activity Monitor after opening 10 tabs with real pages |
| Cold start to first navigate | < 500ms | Time from process launch to first `didFinish` |

---

## 11 · SDK Usage (Target Developer Experience)

```python
from agentbrowser import AgentBrowser

browser = AgentBrowser()  # Connects to /tmp/agentbrowser.sock

# Navigate and wait for full readiness
page = browser.navigate("https://github.com/login", wait_until="idle")

# Get accessibility tree — this is what you send to the LLM
tree = browser.get_accessibility_tree()
# [{"ref": "@e0", "role": "textbox", "name": "Username or email", ...}, ...]

# Act on elements by ref
browser.fill("@e1", "myusername")
browser.fill("@e2", "mypassword")
browser.click("@e3")  # Submit button

# Screenshot for vision models — returns raw bytes
jpeg_bytes = browser.screenshot(quality=70)

# Direct JS when needed
result = browser.evaluate("document.querySelectorAll('a').length")

# Cleanup
browser.close()
```

---

## 12 · Open Questions

1. **Should `click` use JS click or synthesized NSEvent?** JS click is simpler and covers 95% of cases, but some sites detect synthetic clicks. Could offer both: `click` (JS) and `clickNative` (NSEvent dispatch).
2. **Multi-window or tab-based model?** Tabs in one process are simpler. Separate windows give better isolation. Start with tabs, migrate if needed.
3. **Should the binary auto-launch or be started separately?** Starting separately is simpler (agent just connects to socket). Could add auto-launch later via SDK subprocess management.
4. **Content blocking?** `WKContentRuleList` can block ads/trackers for faster loads. Worth adding as an opt-in configuration.
5. **PDF handling?** WKWebView renders PDFs natively. Should `getHTML` return something useful for PDF pages, or add a dedicated `getPDFText` method?
