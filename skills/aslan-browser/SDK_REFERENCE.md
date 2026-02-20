# Aslan Browser Python SDK — Agent Reference

Quick reference for AI agents driving Aslan Browser. Import and go.

---

## Setup

```python
from aslan_browser import AslanBrowser

b = AslanBrowser()  # connects + auto-creates a session for tab tracking
```

Or with context manager (auto-closes all tabs on exit):

```python
with AslanBrowser() as b:
    tab = b.tab_create()
    b.navigate("https://example.com", tab_id=tab)
# tab is auto-closed here — session destroyed on exit
```

The SDK connects to `/tmp/aslan-browser.sock` by default. If Aslan isn't running, it raises `ConnectionError`.

### Auto-Session (Default Behavior)

On connect, the SDK auto-creates a session. Every `tab_create()` call tags the new tab to that session. When the client `close()`s (or the `with` block exits), the session is destroyed and **all tabs created by this client are closed automatically**.

This means you never leak tabs — even if your script crashes, the server detects the disconnect and cleans up.

```python
b = AslanBrowser()
print(b.session_id)   # e.g. "s0" — auto-created
print(b.owned_tabs)   # [] — nothing yet

tab = b.tab_create()
print(b.owned_tabs)   # ["tab1"]

b.close()              # destroys session → closes tab1
```

To opt out and manage sessions manually:
```python
b = AslanBrowser(auto_session=False)
```

**Note:** `tab0` (the default tab created at app startup) is NOT in any session. It survives client cleanup. You can still use it with `b.navigate(url)` (defaults to `tab_id="tab0"`).

---

## Tab & Session Management

```python
# List open tabs → [{"tabId": "tab0", ...}, ...]
tabs = b.tab_list()

# Create a new tab → returns tab ID string (e.g. "tab1")
# Auto-tagged to client session for automatic cleanup
tab = b.tab_create(width=1440, height=900)

# Create tab with a URL pre-loaded
tab = b.tab_create(url="https://example.com")

# Check what tabs this client owns
print(b.owned_tabs)  # ["tab1", "tab2", ...]

# Close a tab explicitly (also removes from local tracking)
b.tab_close(tab)

# Create a manual session for explicit grouping (separate from auto-session)
sid = b.session_create(name="research")
tab = b.tab_create(session_id=sid)  # tags to YOUR session, not auto-session

# List tabs in a session
tabs = b.tab_list(session_id=sid)

# Destroy session + close all its tabs → returns list of closed tab IDs
closed = b.session_destroy(sid)
```

---

## Navigation

```python
# Navigate and wait for page load → {"url": ..., "title": ...}
result = b.navigate("https://example.com", tab_id=tab)

# Wait for full network idle (slower but complete — use for SPAs)
result = b.navigate("https://example.com", tab_id=tab, wait_until="idle")

# Back / forward / reload → {"url": ..., "title": ...}
b.go_back(tab_id=tab)
b.go_forward(tab_id=tab)
b.reload(tab_id=tab)

# Wait for a CSS selector to appear (useful after navigation or clicks)
b.wait_for_selector("div.results", tab_id=tab, timeout=5000)
```

---

## Reading Pages

```python
# Get page title → string
title = b.get_title(tab_id=tab)

# Get current URL → string
url = b.get_url(tab_id=tab)

# Get accessibility tree → list of node dicts
# Each node: {"ref": "@e5", "role": "link", "name": "Click me", "tag": "A", "rect": {...}}
tree = b.get_accessibility_tree(tab_id=tab)

# Get page text content via JS
text = b.evaluate("return document.body.innerText.substring(0, 3000)", tab_id=tab)

# Run any JavaScript — MUST use explicit `return`
value = b.evaluate("return document.querySelectorAll('a').length", tab_id=tab)
```

**CRITICAL:** `evaluate` uses `callAsyncJavaScript` — scripts without `return` return `None`.

---

## Interaction

```python
# Click by accessibility ref (from tree) or CSS selector
b.click("@e5", tab_id=tab)
b.click("button.submit", tab_id=tab)

# Fill an input field
b.fill("@e3", "search text", tab_id=tab)
b.fill("#email", "user@example.com", tab_id=tab)

# Select a dropdown option
b.select("#country", "US", tab_id=tab)

# Press a key
b.keypress("Return", tab_id=tab)
b.keypress("Tab", tab_id=tab)

# Press key with modifiers
b.keypress("a", tab_id=tab, modifiers={"meta": True})  # Cmd+A

# Scroll
b.scroll(x=0, y=500, tab_id=tab)           # scroll page down 500px
b.scroll(x=0, y=-300, target="@e10", tab_id=tab)  # scroll element up
```

**NOTE:** `fill()` sets `.value` — it does NOT work on `contenteditable` divs (Facebook, LinkedIn, Notion). For those, use `evaluate` with `document.execCommand("insertText", false, "text")`.

---

## Screenshots

```python
# Get screenshot as JPEG bytes
jpeg_bytes = b.screenshot(tab_id=tab, quality=70, width=1440)

# Save screenshot directly to file → returns file size in bytes
size = b.save_screenshot("/tmp/page.jpg", tab_id=tab, quality=70, width=1440)
```

---

## Cookies

```python
# Get cookies (optionally filter by URL)
cookies = b.get_cookies(tab_id=tab)
cookies = b.get_cookies(tab_id=tab, url="https://example.com")

# Set a cookie
b.set_cookie("name", "value", ".example.com", path="/", tab_id=tab)
```

---

## Batch Operations (Multi-Tab)

For multi-tab research — do N operations in one round-trip:

```python
# Navigate multiple tabs at once
results = b.parallel_navigate({
    tab1: "https://site-a.com",
    tab2: "https://site-b.com",
    tab3: "https://site-c.com",
}, wait_until="load")
# → {tab1: {"url": ..., "title": ...}, tab2: {...}, ...}

# Get accessibility trees from multiple tabs at once
trees = b.parallel_get_trees([tab1, tab2, tab3])
# → {tab1: [...nodes...], tab2: [...nodes...], ...}

# Take screenshots of multiple tabs at once
screenshots = b.parallel_screenshots([tab1, tab2], quality=70)
# → {tab1: b"...", tab2: b"..."}

# Custom batch (any mix of methods)
responses = b.batch([
    {"method": "getTitle", "params": {"tabId": tab1}},
    {"method": "getURL", "params": {"tabId": tab2}},
    {"method": "evaluate", "params": {"tabId": tab3, "script": "return document.title"}},
])
# → [{"result": {"title": ...}}, {"result": {"url": ...}}, {"result": {"value": ...}}]
```

---

## Error Handling

```python
from aslan_browser import AslanBrowser, AslanBrowserError

try:
    b.navigate("https://example.com", tab_id="nonexistent")
except AslanBrowserError as e:
    print(e.code, e.message)  # -32000, "Tab not found: nonexistent"
```

Common error codes:
- `-32601` — method not found (stale binary or typo)
- `-32602` — invalid params (missing required field)
- `-32000` — tab not found
- `-32001` — JavaScript error in evaluate
- `-32002` — navigation error (ATS blocks `http://`, timeout, etc.)

---

## Gotchas

1. **Always `return` in evaluate scripts.** `b.evaluate("document.title")` → `None`. Use `b.evaluate("return document.title")`.
2. **ATS blocks `http://` URLs.** Always use `https://`. There is no workaround.
3. **`fill()` doesn't work on contenteditable.** Use `evaluate` with `execCommand("insertText")`.
4. **File uploads can't use native picker.** Inject via DataTransfer API in `evaluate`.
5. **`tab0` is the default tab.** If you closed it, create a new tab first.
6. **`wait_until="idle"` is slower but safer for SPAs.** Use `"load"` for static pages.

---

## Typical Agent Session Pattern

```python
from aslan_browser import AslanBrowser

with AslanBrowser() as b:
    # 1. Create a tab (auto-tracked, auto-cleaned on exit)
    tab = b.tab_create()

    # 2. Navigate
    b.navigate("https://example.com", tab_id=tab, wait_until="idle")

    # 3. Read the page
    tree = b.get_accessibility_tree(tab_id=tab)
    # or: text = b.evaluate("return document.body.innerText.substring(0,3000)", tab_id=tab)

    # 4. Interact based on what you see
    b.click("@e5", tab_id=tab)

    # 5. Read again, decide next action
    title = b.get_title(tab_id=tab)

# No manual cleanup needed — `with` block auto-closes all created tabs
```

For multi-tab research:

```python
with AslanBrowser() as b:
    # All tabs auto-tagged to the client's session
    tabs = [b.tab_create() for _ in range(3)]

    b.parallel_navigate({
        tabs[0]: "https://site-a.com",
        tabs[1]: "https://site-b.com",
        tabs[2]: "https://site-c.com",
    }, wait_until="load")

    trees = b.parallel_get_trees(tabs)
    # ... process results ...

# All 3 tabs auto-closed on exit — no manual session_destroy needed
```

For explicit session grouping (separate from auto-cleanup):

```python
with AslanBrowser() as b:
    sid = b.session_create(name="research")
    tabs = [b.tab_create(session_id=sid) for _ in range(3)]
    # ... work ...
    b.session_destroy(sid)  # explicitly close this group
```
