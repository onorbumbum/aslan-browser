# Aslan Browser — Browser Learnings

Discovered patterns, gotchas, and site-specific knowledge. Committed — applies to anyone using Aslan.
Updated by the agent after each session. Load this in full at session start.

---

## 2026-02-19 — Phase 7 binary vs stale /Applications/ binary

`/Applications/aslan-browser.app` is not auto-updated when you build. After any phase, the installed app is stale. Phase 7 features (`session.create`, `batch`) will return `methodNotFound` on the old binary.

**Always launch from DerivedData:**
```bash
pkill -x "aslan-browser" 2>/dev/null; sleep 0.5
open ~/Library/Developer/Xcode/DerivedData/aslan-browser-*/Build/Products/Debug/aslan-browser.app
```

**Probe to confirm Phase 7:** `session.create` must return a `sessionId`. If it returns `methodNotFound`, you're on the wrong binary.

---

## 2026-02-19 — event.navigation interleaves before RPC responses

When `navigate` is called, the socket emits `event.navigation` notification *before* the JSON-RPC response arrives. A reader that grabs the first line gets the notification, not the result.

**Fix:** Always match by `id` field. The `rpc()` helper in SKILL.md already handles this. Never use a raw `sock.recv()` without ID matching.

---

## 2026-02-19 — callAsyncJavaScript requires explicit `return`

Aslan uses WKWebView's `callAsyncJavaScript` under the hood. Scripts without an explicit `return` return `null`.

```python
# Wrong — returns null
rpc('evaluate', {'script': 'document.title'})

# Right
rpc('evaluate', {'script': 'return document.title'})
```

---

## 2026-02-19 — Multi-line JS in batch requests gets mangled

When a multi-line JavaScript string is embedded inside a Python string, passed through JSON, and sent in a `batch` request, backslash escape sequences break silently. The response is `-32001 JavaScript error` with no useful message.

**Rule:** Keep `evaluate` scripts single-line inside `batch` calls.

```python
# Wrong inside batch — multi-line breaks
script = """
var x = document.querySelectorAll('a');
return x.length;
"""

# Right — single line
script = "return document.querySelectorAll('a').length"
```

For standalone `evaluate` calls (not inside batch), multi-line scripts work fine when using `python3 << 'PYEOF'` heredocs.

---

## 2026-02-19 — ATS blocks http:// URLs

macOS App Transport Security blocks plain `http://` URLs even with sandbox disabled. The error is:

```
Navigation error (-32002): The resource could not be loaded because the App Transport Security
policy requires the use of a secure connection.
```

Small local businesses (dentists, shops) often still have HTTP-only sites. Always upgrade before navigating:

```python
if url.startswith('http://'):
    url = 'https://' + url[7:]
```

If `https://` also fails, the site likely has no HTTPS — skip it.

---

## 2026-02-19 — Google #:~:text= fragment links create duplicate tabs

Google SERPs include "Read more" anchor links using text fragment syntax: `https://example.com/#:~:text=some+snippet`. These resolve to the same page as the canonical result link. Scraping all `<a href>` tags without filtering produces duplicate tab pairs.

**Fix in the JS scraper:**
```javascript
if (href.includes('#:~:text=')) continue;
```

Or in Python after scraping:
```python
from urllib.parse import urldefrag
href, _ = urldefrag(href)
```

---

## 2026-02-19 — Closing all tabs leaves zero — socket stays alive

After `tab.close` on all tabs, `tab.list` returns `[]`. This is expected. The socket server remains running. Create new tabs with `tab.create` whenever needed.

---

## 2026-02-19 — batch + session is the efficient pattern for multi-tab research

For any task involving opening multiple result pages:

1. `session.create` — isolate this task's tabs
2. `tab.create` × N with `sessionId` — tag all result tabs
3. `batch` navigate — load all pages in one round-trip
4. `batch` evaluate — read all pages in one round-trip
5. `session.destroy` — close all tabs at once when done

This reduces a 14+ sequential call flow to ~5 calls total. Use it for any research task with 3+ tabs.

---

## 2026-02-19 — WKWebView custom User-Agent required for Google/Gmail/LinkedIn

WKWebView's default UA is classified by Google/Gmail/LinkedIn as an unsupported embedded browser, showing banners or blocking login. Aslan sets a Chrome UA by default (added in real-world testing phase):

```
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36
```

This is baked into the app. No action needed. But if a site blocks or degrades, check the UA first.

---

## 2026-02-19 — contenteditable / rich text fields require execCommand, not fill()

Sites like Facebook, Notion, and LinkedIn use `contenteditable` divs for text input. The SDK's `fill()` sets `.value` which has no effect on `contenteditable`.

**Workaround via evaluate:**
```python
rpc('evaluate', {'tabId': 'tab0', 'script': '''
    var ed = document.querySelector("[contenteditable=true]");
    ed.focus();
    document.execCommand("insertText", false, "your text here");
    return "ok";
'''})
```

---

## 2026-02-19 — SDK auto-session eliminates tab leaks (v1.2.0)

As of SDK v0.2.0 / app v1.2.0, the Python SDK auto-creates a session on connect and tags every `tab_create()` call to it. When the `with` block exits or `close()` is called, `session.destroy` fires and all created tabs are closed.

**Server-side belt-and-suspenders:** If the script crashes without calling `close()`, the server's `JSONRPCHandler` detects the socket disconnect and auto-destroys all sessions owned by that connection.

**What this means for agents:**
- You no longer need manual `session_create` / `session_destroy` for cleanup. Just use `with AslanBrowser() as b:` and `tab_create()`.
- `b.owned_tabs` shows what this client has created.
- `b.session_id` shows the auto-session ID.
- `tab0` (the default startup tab) is NOT in any session — it survives cleanup.
- To opt out: `AslanBrowser(auto_session=False)`.

**Old pattern (still works but unnecessary):**
```python
sid = b.session_create(name="research")
tabs = [b.tab_create(session_id=sid) for _ in range(3)]
# ... work ...
b.session_destroy(sid)
```

**New pattern (preferred):**
```python
with AslanBrowser() as b:
    tabs = [b.tab_create() for _ in range(3)]
    # ... work ...
# all tabs auto-closed
```

---

## 2026-02-19 — File upload without native picker via DataTransfer API

WKWebView file input clicks open a native macOS file picker that cannot be automated. Inject files via the DataTransfer API instead:

```python
import base64
b64 = base64.b64encode(open('/path/to/file', 'rb').read()).decode()
rpc('evaluate', {'tabId': 'tab0', 'script': f'''
    var input = document.querySelector("input[type=file]");
    var binary = atob("{b64}");
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    var file = new File([bytes], "filename.png", {{type: "image/png"}});
    var dt = new DataTransfer();
    dt.items.add(file);
    input.files = dt.files;
    input.dispatchEvent(new Event("change", {{bubbles: true}}));
    return "ok";
'''})
```
