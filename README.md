<p align="center">
  <img src="assets/logo.png" width="180" alt="Aslan Browser logo">
</p>

<h1 align="center">Aslan Browser</h1>

<p align="center">
  A native macOS browser for AI agents.<br>
  WKWebView + Unix socket + JSON-RPC.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/swift-6.2-orange" alt="Swift 6.2">
  <img src="https://img.shields.io/badge/python-3.10%2B-green" alt="Python 3.10+">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT License">
</p>

---

## Why Aslan?

Browser automation tools like Puppeteer, Playwright, and Selenium weren't designed with AI agents in mind. They ship a full Chrome, communicate over HTTP/CDP, and hand you the entire DOM when all your agent needs is "what's on the page and what can I click."

Aslan wraps macOS's built-in WKWebView and exposes it over a Unix socket. No Chrome download. The Python SDK uses only stdlib. And instead of dumping raw DOM, it gives you an accessibility tree, which is 10-100x fewer tokens for the same page.

- **Native macOS.** WKWebView, not Chrome. No 500MB browser download.
- **Fast.** Sub-2ms JS eval, sub-30ms screenshots. Unix socket, not HTTP.
- **Accessibility-tree-first.** 10-100x fewer tokens than raw DOM for the same page.
- **Zero-dependency Python SDK.** Only stdlib (`socket`, `json`, `asyncio`, `base64`).
- **Simple protocol.** NDJSON JSON-RPC 2.0. You can build a client in any language.

---

## Table of Contents

- [Quickstart](#quickstart)
- [Installation](#installation)
  - [Option A: Build from Source](#option-a-build-from-source)
  - [Option B: Download Pre-built Binary](#option-b-download-pre-built-binary)
- [Python SDK](#python-sdk)
- [AI Agent Skill](#ai-agent-skill)
- [Usage Examples](#usage-examples)
- [API Reference](#api-reference)
- [Architecture](#architecture)
- [Performance](#performance)
- [Project Structure](#project-structure)
- [Development](#development)
- [License](#license)

---

## Quickstart

```python
from aslan_browser import AslanBrowser

with AslanBrowser() as browser:
    # Navigate and wait for the page to be ready
    browser.navigate("https://github.com/login", wait_until="idle")

    # Get the accessibility tree (this is what you send to the LLM)
    tree = browser.get_accessibility_tree()
    for node in tree:
        print(f"{node['ref']} {node['role']} \"{node['name']}\"")
    # @e0 textbox "Username or email address"
    # @e1 textbox "Password"
    # @e2 button "Sign in"

    # Interact using @eN refs from the tree
    browser.fill("@e0", "myusername")
    browser.fill("@e1", "mypassword")
    browser.click("@e2")

    # Screenshot for vision models
    browser.save_screenshot("page.jpg")
```

Navigate, read the tree, act on refs. The accessibility tree is the key idea here. Your agent gets a compact list of what's interactive on the page, each tagged with a ref like `@e0`, and uses those refs to click/fill/select.

---

## Installation

### Prerequisites

| Requirement | Version | Check |
|---|---|---|
| macOS | 14.0+ (Sonoma) | `sw_vers` |
| Xcode | 16+ (Swift 6.2) | `xcodebuild -version` |
| Python | 3.10+ | `python3 --version` |

### Option A: Build from Source

**1. Clone and build the macOS app**

```bash
git clone https://github.com/onorbumbum/aslan-browser.git
cd aslan-browser

# Build with Xcode
xcodebuild build \
  -scheme aslan-browser \
  -configuration Debug \
  -derivedDataPath .build
```

The app will be at `.build/Build/Products/Debug/aslan-browser.app`.

**2. Install the Python SDK**

```bash
cd sdk/python
pip install -e .
```

**3. Start the browser**

```bash
# Visible window (for development / debugging)
.build/Build/Products/Debug/aslan-browser.app/Contents/MacOS/aslan-browser

# Hidden window (for production / CI)
.build/Build/Products/Debug/aslan-browser.app/Contents/MacOS/aslan-browser --hidden
```

The app listens on `/tmp/aslan-browser.sock`. Your Python code connects there automatically.

**4. Verify it works**

```bash
python3 -c "
from aslan_browser import AslanBrowser
with AslanBrowser() as b:
    b.navigate('https://example.com')
    print('Title:', b.get_title())
    print('Nodes:', len(b.get_accessibility_tree()))
"
```

### Option B: Download Pre-built Binary

Download the latest `.zip` from [**Releases**](https://github.com/onorbumbum/aslan-browser/releases).

| Build | Architecture |
|---|---|
| `aslan-browser-macos-universal.zip` | **Universal (arm64 + x86_64)**, recommended |
| `aslan-browser-macos-arm64.zip` | Apple Silicon only |
| `aslan-browser-macos-x86_64.zip` | Intel only |

```bash
# 1. Download and unzip (universal works on all Macs)
curl -L -o aslan-browser.zip \
  https://github.com/onorbumbum/aslan-browser/releases/latest/download/aslan-browser-macos-universal.zip
unzip aslan-browser.zip

# 2. Clear quarantine flag (first run only, dev-signed, not notarized)
xattr -cr aslan-browser.app

# 3. Start the browser
./aslan-browser.app/Contents/MacOS/aslan-browser --hidden

# 4. Install the Python SDK (from source for now)
git clone https://github.com/onorbumbum/aslan-browser.git
pip install -e aslan-browser/sdk/python
```

Requires macOS 14.0+ (Sonoma). The universal build runs natively on both Apple Silicon and Intel Macs.

---

## Python SDK

### Install

```bash
pip install aslan-browser    # from PyPI (coming soon)
# or
pip install -e sdk/python    # from source
```

### Sync Client

```python
from aslan_browser import AslanBrowser

with AslanBrowser() as browser:
    browser.navigate("https://example.com")
    tree = browser.get_accessibility_tree()
    data = browser.screenshot()
```

### Async Client

```python
from aslan_browser import AsyncAslanBrowser

async with AsyncAslanBrowser() as browser:
    await browser.navigate("https://example.com")
    tree = await browser.get_accessibility_tree()
    data = await browser.screenshot()
```

### Event Handling (Async)

```python
async with AsyncAslanBrowser() as browser:
    def on_event(msg):
        print(f"Event: {msg['method']} → {msg.get('params', {})}")

    browser.on_event(on_event)
    await browser.navigate("https://example.com")
```

### Custom Socket Path

```python
browser = AslanBrowser(socket_path="/tmp/my-custom.sock")
```

---

## AI Agent Skill

Aslan ships a **skill** — a structured instruction set that teaches AI coding agents (Claude, GPT, etc.) how to drive the browser effectively. It follows the [Prompts-are-Code](docs/prompts-are-code.md) methodology: the skill is a program that executes on the LLM.

The skill lives in `skills/aslan-browser/` and includes:

```
skills/aslan-browser/
├── SKILL.md                    # Instructions — the "program" the agent follows
└── learnings/
    ├── browser.md              # Discovered gotchas and patterns (committed, grows over time)
    └── user.md                 # User-specific preferences (gitignored)
```

| File | Purpose |
|---|---|
| `SKILL.md` | Teaches the agent to use the Python SDK, drive interactively (navigate → read → decide → act), handle multi-tab research, and avoid known pitfalls |
| `learnings/browser.md` | Runtime discoveries — ATS quirks, contenteditable workarounds, site-specific patterns. Agents load this at session start so they don't repeat past mistakes |
| `learnings/user.md` | Your personal preferences and workflows. Gitignored — stays on your machine |

The SDK Reference at [`sdk/python/SDK_REFERENCE.md`](sdk/python/SDK_REFERENCE.md) is the agent's cheat sheet for all available methods.

### Installing the Skill

The skill needs to be accessible from your agent's skill directory. The cleanest approach is a **symlink** — one source of truth, edits go to one place, `git pull` updates the skill.

```bash
# For pi agents (default skill path: ~/.pi/agent/skills/)
ln -s /path/to/aslan-browser/skills/aslan-browser ~/.pi/agent/skills/aslan-browser
```

Your agent framework may use a different skill directory. Point the symlink wherever your agent loads skills from.

### How It Works

When your agent gets a browsing task, it loads the skill and follows this loop:

1. **Setup** — Load `SDK_REFERENCE.md` + `learnings/browser.md` + `learnings/user.md` into context
2. **Verify** — Check that Aslan is running via the SDK
3. **Drive interactively** — Navigate → read the page → decide next action → act → repeat
4. **Self-improve** — After the task, append any new discoveries to `learnings/browser.md`

The learnings files are the skill's persistent memory. Each session starts by loading them, and ends by appending anything new. Over time, the skill gets smarter about site-specific quirks, workarounds, and efficient patterns.

---

## Usage Examples

### Agent Workflow

The core loop: read the page, let the LLM decide, act on its choice.

```python
from aslan_browser import AslanBrowser

with AslanBrowser() as browser:
    browser.navigate("https://news.ycombinator.com", wait_until="idle")

    # 1. Read: get the accessibility tree
    tree = browser.get_accessibility_tree()

    # 2. Send to LLM (tree is a compact list of interactive elements)
    # Each node: {"ref": "@e0", "role": "link", "name": "Show HN: ...", "rect": {...}}

    # 3. Act: use the ref the LLM picks
    browser.click("@e5")  # click the 5th element
```

### Screenshots

```python
# JPEG bytes, send directly to GPT-4V, Claude, etc.
jpeg_bytes = browser.screenshot(quality=70)

# Or save to disk
browser.save_screenshot("page.jpg", quality=85, width=1440)
```

### Multi-Tab

```python
with AslanBrowser() as browser:
    # Default tab0 is created on launch
    tab1 = browser.tab_create(url="https://google.com")
    tab2 = browser.tab_create(url="https://github.com")

    # Work with specific tabs
    browser.navigate("https://example.com", tab_id="tab0")
    tree1 = browser.get_accessibility_tree(tab_id=tab1)
    tree2 = browser.get_accessibility_tree(tab_id=tab2)

    # List all tabs
    tabs = browser.tab_list()

    # Close when done
    browser.tab_close(tab1)
    browser.tab_close(tab2)
```

### Batch Operations

Multiple operations in a single round-trip. Useful when you have several agents or tabs going at once.

```python
with AslanBrowser() as browser:
    tab1 = browser.tab_create(url="https://google.com")
    tab2 = browser.tab_create(url="https://github.com")

    # Navigate multiple tabs at once
    results = browser.parallel_navigate({
        tab1: "https://news.ycombinator.com",
        tab2: "https://reddit.com",
    })

    # Get all accessibility trees in one call
    trees = browser.parallel_get_trees([tab1, tab2])

    # Screenshot all tabs at once
    screenshots = browser.parallel_screenshots([tab1, tab2])
```

### Sessions

Sessions let you isolate tabs for different agents. Destroying a session closes all its tabs.

```python
with AslanBrowser() as browser:
    session1 = browser.session_create(name="agent-research")
    session2 = browser.session_create(name="agent-shopping")

    tab_a = browser.tab_create(url="https://google.com", session_id=session1)
    tab_b = browser.tab_create(url="https://amazon.com", session_id=session2)

    research_tabs = browser.tab_list(session_id=session1)

    browser.session_destroy(session1)
```

### Cookies

```python
with AslanBrowser() as browser:
    # Set a cookie before navigating
    browser.set_cookie(
        name="session",
        value="abc123",
        domain=".example.com",
    )
    browser.navigate("https://example.com")

    # Read cookies
    cookies = browser.get_cookies(url="https://example.com")
```

### Keyboard and Forms

```python
with AslanBrowser() as browser:
    browser.navigate("https://example.com/search")

    browser.fill("@e1", "search query")
    browser.keypress("Enter")

    # Keyboard shortcuts
    browser.keypress("a", modifiers={"meta": True})  # Cmd+A

    # Select from dropdown
    browser.select("@e3", "option-value")

    # Scroll
    browser.scroll(x=0, y=500)  # scroll down 500px
```

### Direct JavaScript

```python
with AslanBrowser() as browser:
    browser.navigate("https://example.com")

    count = browser.evaluate("return document.querySelectorAll('a').length")
    print(f"Found {count} links")

    # With arguments
    result = browser.evaluate(
        "return document.querySelector(sel).textContent",
        args={"sel": "h1"}
    )
```

---

## API Reference

All methods default to `tab_id="tab0"` for single-tab usage.

### Navigation

| Method | Description |
|---|---|
| `navigate(url, tab_id, wait_until, timeout)` | Navigate to URL. `wait_until`: `"none"`, `"load"`, `"idle"` |
| `go_back(tab_id)` | Navigate back |
| `go_forward(tab_id)` | Navigate forward |
| `reload(tab_id)` | Reload the page |
| `wait_for_selector(selector, tab_id, timeout)` | Wait for a CSS selector to appear |

### Page Info

| Method | Description |
|---|---|
| `get_title(tab_id)` | Get page title |
| `get_url(tab_id)` | Get current URL |
| `evaluate(script, tab_id, args)` | Execute JavaScript, return result |

### Accessibility Tree

| Method | Description |
|---|---|
| `get_accessibility_tree(tab_id)` | Extract the accessibility tree as a flat list |

Each node returns:
```json
{"ref": "@e0", "role": "link", "name": "Click me", "rect": {"x": 10, "y": 50, "w": 80, "h": 24}}
```

Use `ref` values (`@e0`, `@e1`, ...) in `click()`, `fill()`, etc.

### Interaction

| Method | Description |
|---|---|
| `click(target, tab_id)` | Click by `@eN` ref or CSS selector |
| `fill(target, value, tab_id)` | Fill an input field |
| `select(target, value, tab_id)` | Select a dropdown option |
| `keypress(key, tab_id, modifiers)` | Send a keypress (`"Enter"`, `"Tab"`, etc.) |
| `scroll(x, y, target, tab_id)` | Scroll the page or an element |

### Screenshots

| Method | Description |
|---|---|
| `screenshot(tab_id, quality, width)` | Take screenshot, returns JPEG `bytes` |
| `save_screenshot(path, tab_id, quality, width)` | Save screenshot to file |

### Cookies

| Method | Description |
|---|---|
| `get_cookies(tab_id, url)` | Get cookies, optionally filtered by URL |
| `set_cookie(name, value, domain, path, expires, tab_id)` | Set a cookie |

### Tab Management

| Method | Description |
|---|---|
| `tab_create(url, width, height, hidden, session_id)` | Create a new tab, returns tab ID |
| `tab_close(tab_id)` | Close a tab |
| `tab_list(session_id)` | List all open tabs |

### Sessions

| Method | Description |
|---|---|
| `session_create(name)` | Create a named session, returns session ID |
| `session_destroy(session_id)` | Destroy session and close all its tabs |

### Batch / Parallel

| Method | Description |
|---|---|
| `batch(requests)` | Execute multiple JSON-RPC calls in one round-trip |
| `parallel_navigate(urls, wait_until)` | Navigate multiple tabs simultaneously |
| `parallel_get_trees(tab_ids)` | Get accessibility trees from multiple tabs |
| `parallel_screenshots(tab_ids, quality, width)` | Screenshot multiple tabs at once |

---

## Architecture

```
┌──────────────────┐    Unix Socket    ┌──────────────────────────────────────┐
│  Python SDK      │◄─────────────────►│  aslan-browser.app (macOS native)   │
│  (or any client) │   NDJSON JSON-RPC │                                      │
└──────────────────┘                   │  SocketServer (SwiftNIO)             │
                                       │  └─ JSONRPCHandler                   │
                                       │     └─ MethodRouter                  │
                                       │        └─ TabManager                 │
                                       │           └─ BrowserTab              │
                                       │              ├─ WKWebView            │
                                       │              └─ ScriptBridge (JS)    │
                                       └──────────────────────────────────────┘
```

### Design Decisions

| Decision | Choice | Why |
|---|---|---|
| Rendering engine | WKWebView | macOS native, no Chrome dependency, full JS/WebSocket support |
| Server | SwiftNIO + Unix socket | ~30% faster than TCP for local IPC, no port conflicts |
| Protocol | NDJSON JSON-RPC 2.0 | Language-agnostic, one message per line |
| Window strategy | Hidden NSWindow per tab | Invisible but in window hierarchy so JS/WebSockets work normally |
| Page representation | Accessibility tree | 10-100x fewer tokens than raw DOM |

### How the Accessibility Tree Works

Injected JavaScript (`ScriptBridge.swift`) walks the DOM and produces a flat list of interactive and semantic elements. It traverses all visible elements, filters down to things you'd actually interact with (links, buttons, inputs, selects, ARIA landmarks), and assigns each a stable `@eN` ref. Elements get tagged with `data-agent-ref` attributes so `click`/`fill` can find them later.

Names are resolved by checking `aria-label`, then `aria-labelledby`, then `<label>`, `placeholder`, `title`, and finally visible text content (truncated at 80 chars). Bounding rects are included for spatial reasoning.

When you call `click("@e3")`, the browser finds the element with `data-agent-ref="@e3"` and dispatches the event.

---

## Performance

Benchmarked on Apple Silicon (M-series). Run them yourself:

```bash
# Start the app first, then:
python3 benchmarks/benchmark.py
```

| Benchmark | Target | Typical Result |
|---|---|---|
| JS eval round-trip (`1+1`) | < 2ms | ~0.5ms |
| Screenshot (1440w, JPEG q70) | < 30ms | ~15ms |
| Accessibility tree (simple page) | < 50ms | ~5ms |
| Accessibility tree (complex page) | < 50ms | ~20ms |

### vs. Puppeteer/CDP

| Operation | Aslan Browser | Puppeteer + Chrome |
|---|---|---|
| JS eval round-trip | ~0.5ms | 2-5ms |
| Screenshot | ~15ms | 50-150ms |
| Memory per tab | ~40MB | ~80-150MB |
| Cold start | < 500ms | 2-5s |
| Page representation | A11y tree (compact) | Full DOM |

---

## Project Structure

```
aslan-browser/
├── aslan-browser/              # Swift source (AppKit + SwiftNIO)
│   ├── AppDelegate.swift       # App lifecycle, menu, starts server
│   ├── BrowserTab.swift        # WKWebView wrapper, navigation, screenshots
│   ├── TabManager.swift        # Tab lifecycle, session management
│   ├── SocketServer.swift      # SwiftNIO Unix socket listener
│   ├── JSONRPCHandler.swift    # JSON-RPC 2.0 parser + response builder
│   ├── MethodRouter.swift      # Maps JSON-RPC methods to BrowserTab calls
│   ├── ScriptBridge.swift      # Injected JS: a11y tree, readiness, interaction
│   └── Models/
│       ├── RPCMessage.swift
│       ├── A11yNode.swift
│       ├── BrowserError.swift
│       └── TabInfo.swift
├── sdk/
│   └── python/
│       ├── aslan_browser/
│       │   ├── client.py       # Sync client
│       │   └── async_client.py # Async client
│       ├── SDK_REFERENCE.md    # Agent-facing cheat sheet for all SDK methods
│       ├── tests/
│       └── pyproject.toml
├── skills/
│   └── aslan-browser/
│       ├── SKILL.md            # AI agent instructions (Prompts-are-Code)
│       └── learnings/
│           ├── browser.md      # Discovered patterns and gotchas (committed)
│           └── user.md         # User-specific preferences (gitignored)
├── benchmarks/
│   ├── benchmark.py
│   └── complex_page.html
├── tests/                      # Integration tests
├── docs/                       # Design docs and phase plans
├── assets/
└── aslan-browser.xcodeproj
```

~2,000 lines of Swift, ~600 lines of Python. Two external dependencies (SwiftNIO).

---

## Development

### Build and Run

```bash
# Build
xcodebuild build -scheme aslan-browser -configuration Debug -derivedDataPath .build

# Run (visible)
.build/Build/Products/Debug/aslan-browser.app/Contents/MacOS/aslan-browser

# Run (hidden)
.build/Build/Products/Debug/aslan-browser.app/Contents/MacOS/aslan-browser --hidden
```

### Run Tests

```bash
# Start the app first, then:
cd sdk/python
pip install -e ".[dev]"
python3 -m pytest tests/ -v
```

### Run Benchmarks

```bash
# Start the app first, then:
python3 benchmarks/benchmark.py
```

### Build a Release Binary

```bash
xcodebuild build \
  -scheme aslan-browser \
  -configuration Release \
  -derivedDataPath .build

# The release app is at:
# .build/Build/Products/Release/aslan-browser.app
```

To distribute the `.app` bundle, zip it:

```bash
cd .build/Build/Products/Release
zip -r aslan-browser-macos.zip aslan-browser.app
```

---

## Troubleshooting

### "Socket not found" error

The app isn't running. Start it first:

```bash
.build/Build/Products/Debug/aslan-browser.app/Contents/MacOS/aslan-browser --hidden
```

### "Connection refused" error

Another instance may be running. Kill it and restart:

```bash
pkill -f aslan-browser
rm -f /tmp/aslan-browser.sock
# Then restart the app
```

### Blank screenshots

WKWebView needs a window hierarchy to render. Make sure you're using the app, not trying to run headless without it. The `--hidden` flag hides the window but keeps it in the hierarchy.

### Sites detecting automation

Aslan uses a Chrome-compatible User-Agent string by default. Some sites may still detect automation. You can set a custom one:

```python
browser.evaluate("""
    Object.defineProperty(navigator, 'userAgent', {
        get: () => 'your-custom-user-agent'
    });
""")
```

---

## JSON-RPC Protocol (For Non-Python Clients)

Connect to the Unix socket at `/tmp/aslan-browser.sock` and send newline-delimited JSON-RPC 2.0:

```bash
# Example with socat
echo '{"jsonrpc":"2.0","id":1,"method":"navigate","params":{"tabId":"tab0","url":"https://example.com"}}' | \
  socat - UNIX-CONNECT:/tmp/aslan-browser.sock
```

One JSON line per request. One JSON line per response. Notifications (events) come as JSON lines without an `id` field.

The [Python SDK source](sdk/python/aslan_browser/client.py) is a complete client implementation in under 300 lines, no dependencies. Read it if you want to build a client in another language.

---

## Roadmap

- [x] Pre-built binaries on GitHub Releases
- [ ] `pip install aslan-browser` on PyPI
- [ ] Content blocking (ad/tracker filtering via `WKContentRuleList`)
- [ ] PDF text extraction
- [ ] Network request visibility (URL-level via fetch/XHR monkey-patching)
- [ ] File download handling
- [ ] Node.js / TypeScript SDK
- [ ] Auto-launch: SDK starts the app if it's not running

---

## License

MIT. See [LICENSE](LICENSE).
