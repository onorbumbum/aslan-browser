# aslan-browser

A native macOS browser for AI agents. WKWebView + Unix socket + JSON-RPC = fast, simple browser automation without Chrome or CDP.

## What Is This?

aslan-browser is a lightweight macOS app that wraps WKWebView and exposes a JSON-RPC API over a Unix socket (`/tmp/aslan-browser.sock`). AI agents connect, navigate pages, extract accessibility trees, fill forms, click buttons, and take screenshots — all through a clean Python SDK with zero external dependencies.

## Installation

### 1. Build the macOS app

```bash
cd aslan-browser
xcodebuild build -scheme aslan-browser -configuration Debug -derivedDataPath .build
```

### 2. Install the Python SDK

```bash
cd sdk/python
pip install -e .
```

### 3. Start the app

```bash
# Visible (for development/debugging)
.build/Build/Products/Debug/aslan-browser.app/Contents/MacOS/aslan-browser

# Hidden (for production/CI)
.build/Build/Products/Debug/aslan-browser.app/Contents/MacOS/aslan-browser --hidden
```

## Quickstart

```python
from aslan_browser import AslanBrowser

with AslanBrowser() as browser:
    # Navigate
    browser.navigate("https://github.com/login", wait_until="idle")

    # Extract accessibility tree
    tree = browser.get_accessibility_tree()
    for node in tree:
        print(f"{node['ref']} {node['role']} \"{node['name']}\"")

    # Interact using @eN refs from the tree
    browser.fill("@e1", "myusername")
    browser.fill("@e2", "mypassword")
    browser.click("@e3")

    # Screenshot
    jpeg_bytes = browser.screenshot(quality=70)

    # Or save directly
    browser.save_screenshot("page.jpg")
```

### Async Usage

```python
from aslan_browser import AsyncAslanBrowser

async with AsyncAslanBrowser() as browser:
    await browser.navigate("https://example.com")
    tree = await browser.get_accessibility_tree()
    data = await browser.screenshot()
```

## API Reference

All methods default `tab_id="tab0"` for single-tab usage.

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
| `get_accessibility_tree(tab_id)` | Extract the accessibility tree as a list of nodes |

Each node: `{"ref": "@e0", "role": "link", "name": "Click me", "rect": {...}}`

### Interaction

| Method | Description |
|---|---|
| `click(target, tab_id)` | Click by `@eN` ref or CSS selector |
| `fill(target, value, tab_id)` | Fill an input field |
| `select(target, value, tab_id)` | Select an option |
| `keypress(key, tab_id, modifiers)` | Send a keypress |
| `scroll(x, y, target, tab_id)` | Scroll the page or element |

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
| `tab_create(url, width, height, hidden)` | Create a new tab, returns tab ID |
| `tab_close(tab_id)` | Close a tab |
| `tab_list()` | List all open tabs |

## Architecture

```
┌──────────────┐    Unix Socket    ┌──────────────────────────────────┐
│  Python SDK  │◄──────────────────►  aslan-browser (macOS app)      │
│  (client.py) │   NDJSON JSON-RPC │                                  │
└──────────────┘                   │  SocketServer (SwiftNIO)         │
                                   │  └─ JSONRPCHandler               │
                                   │     └─ MethodRouter              │
                                   │        └─ TabManager             │
                                   │           └─ BrowserTab          │
                                   │              ├─ WKWebView        │
                                   │              └─ ScriptBridge (JS)│
                                   └──────────────────────────────────┘
```

- **Protocol**: NDJSON JSON-RPC 2.0 over Unix socket at `/tmp/aslan-browser.sock`
- **No HTTP**: Raw socket, newline-delimited JSON. No HTTP overhead.
- **No external dependencies**: Python SDK uses only stdlib (`socket`, `json`, `asyncio`, `base64`).
- **macOS native**: WKWebView for rendering. AppKit for window management. SwiftNIO for the socket server.

## Development

### Run integration tests

```bash
# Start the app first, then:
cd sdk/python && python3 -m pytest tests/ -v
```

### Run benchmarks

```bash
# Start the app first, then:
python3 benchmarks/benchmark.py
```

### Project Structure

```
aslan-browser/
├── aslan-browser/          # Swift source (AppKit + SwiftNIO)
│   ├── AppDelegate.swift
│   ├── BrowserTab.swift    # WKWebView wrapper
│   ├── TabManager.swift    # Tab lifecycle
│   ├── SocketServer.swift  # SwiftNIO Unix socket
│   ├── JSONRPCHandler.swift
│   ├── MethodRouter.swift  # JSON-RPC method dispatch
│   ├── ScriptBridge.swift  # Injected JS bridge
│   └── Models/
├── sdk/python/             # Python SDK
│   ├── aslan_browser/
│   │   ├── client.py       # Sync client
│   │   └── async_client.py # Async client
│   └── tests/
└── benchmarks/
```

## Requirements

- macOS 15.0+
- Xcode 16+ (Swift 6.2)
- Python 3.10+
