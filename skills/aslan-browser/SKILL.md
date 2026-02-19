---
name: aslan-browser
description: Drive the Aslan Browser for web browsing, scraping, research, automation, and multi-tab tasks. Aslan is a native macOS AI browser controlled via JSON-RPC over a Unix socket. Load this skill whenever the user asks to browse, search, open tabs, scrape pages, or interact with websites using Aslan.
---

# Aslan Browser

Aslan is a native macOS WKWebView browser controlled via a Python SDK over `/tmp/aslan-browser.sock`. Purpose-built for agent-driven browsing.

---

## ⚠️ CRITICAL: Read These Before Anything Else

**1. You drive Aslan interactively. You do NOT pre-write scripts.**

Each bash call is one live action. Navigate, read what loaded, decide the next step from what you actually see. This is not a scripting tool — it is a live browser you are piloting.

```
navigate → read result → decide next action → act → read result → ...
```

DO NOT write a full script before running anything.
DO NOT plan more than one step ahead without first seeing what the page returns.

**2. Use the Python SDK. Do NOT write raw socket code.**

The SDK is installed and handles connection management, event interleaving, retries, and error handling. Never paste raw `rpc()` functions or socket boilerplate.

**3. Load your learnings before starting any task.**

Run the setup step below. It loads discovered knowledge from past sessions so you don't repeat mistakes.

---

## 1. Setup — Run This at the Start of Every Session

### 1a. Load knowledge (parallel reads)

Read ALL of these files in full at session start. They are Tier 1 context — always needed.

1. **SDK Reference** — what methods are available and how to call them:
   `~/_PROJECTS/aslan-browser/aslan-browser/sdk/python/SDK_REFERENCE.md`

2. **Browser learnings** — gotchas and patterns discovered in past sessions (committed):
   `learnings/browser.md`

3. **User learnings** — user-specific preferences and workflows (gitignored, may not exist):
   `learnings/user.md`

Read all three in parallel. The SDK Reference tells you *what you can do*. The learnings tell you *what to watch out for*.

### 1b. Verify Aslan is running

```python
python3 -c "
from aslan_browser import AslanBrowser
try:
    b = AslanBrowser()
    sid = b.session_create()
    print(f'Connected. Session: {sid}')
    b.close()
except Exception as e:
    print(f'NOT RUNNING: {e}')
"
```

- If connected → proceed.
- If connection error → Aslan is not running. Launch it:

```bash
pkill -x "aslan-browser" 2>/dev/null; sleep 0.5
open ~/Library/Developer/Xcode/DerivedData/aslan-browser-*/Build/Products/Debug/aslan-browser.app
sleep 2
echo "Relaunched"
```

CRITICAL: Always launch from DerivedData. `/Applications/aslan-browser.app` may be a stale build.

---

## 2. The Python SDK — The Only Way to Talk to Aslan

The SDK is already installed. Use it in every `python3 << 'PYEOF'` block:

```python
from aslan_browser import AslanBrowser

b = AslanBrowser()
# ... do work ...
b.close()
```

Or with context manager:

```python
from aslan_browser import AslanBrowser

with AslanBrowser() as b:
    tab = b.tab_create()
    b.navigate("https://example.com", tab_id=tab, wait_until="idle")
    text = b.evaluate("return document.body.innerText.substring(0, 3000)", tab_id=tab)
    print(text)
```

**The SDK handles:**
- Connection with retry
- Event/notification interleaving (skips `event.navigation` automatically)
- ID matching on responses
- Proper error types (`AslanBrowserError` with code + message)

For the full method reference, see the SDK Reference loaded in Step 1a.

DO NOT reimplement any of this. DO NOT write raw socket code. DO NOT paste `rpc()` helpers.

---

## 3. Interactive Driving Protocol

This is the main loop. Follow it for every browsing task.

```
STEP 1 — Orient: What tabs exist? What is currently loaded?
  → b.tab_list()
  → b.get_title(tab_id=tab) / b.get_url(tab_id=tab)

STEP 2 — Act: Take ONE action based on what you see.
  → navigate / click / fill / keypress / evaluate

STEP 3 — Read: What did that action produce?
  → b.evaluate("return document.body.innerText.substring(0,3000)", tab_id=tab)
  → b.get_accessibility_tree(tab_id=tab)
  → b.get_title(tab_id=tab)

STEP 4 — Decide: What is the next single action?
  → Go to STEP 2, or finish.
```

**Multi-tab research pattern:**
```python
with AslanBrowser() as b:
    sid = b.session_create(name="research")
    tabs = [b.tab_create(session_id=sid) for _ in range(3)]
    b.parallel_navigate({tabs[0]: url1, tabs[1]: url2, tabs[2]: url3})
    trees = b.parallel_get_trees(tabs)
    # ... process ...
    b.session_destroy(sid)
```

Use `session.create` + session-tagged `tab_create` when opening multiple tabs. Use `session_destroy` to clean up all at once.

Use `parallel_navigate` / `parallel_get_trees` / `batch` ONLY after you already know what to do with each tab. Not as a substitute for interactive exploration.

---

## 4. Combining Multiple Operations Per Call

You do NOT need a separate bash call for every single SDK method. Chain related operations in one heredoc block:

```python
python3 << 'PYEOF'
from aslan_browser import AslanBrowser

with AslanBrowser() as b:
    # Orient
    tabs = b.tab_list()
    if not tabs:
        tab = b.tab_create()
    else:
        tab = tabs[0]["tabId"]

    # Act
    b.navigate("https://example.com", tab_id=tab, wait_until="idle")

    # Read
    title = b.get_title(tab_id=tab)
    text = b.evaluate("return document.body.innerText.substring(0, 3000)", tab_id=tab)
    print(f"Title: {title}")
    print(f"Text: {text}")
PYEOF
```

One heredoc per logical step. NOT one heredoc per SDK call. NOT a giant script that pre-plans 10 steps before seeing any page.

---

## 5. Self-Improvement Protocol

CRITICAL: After completing any browsing task, check — did you discover anything new?

### What qualifies as a discovery?

Ask yourself: *"If I had known this at the start of this session, would it have saved me time or prevented a mistake?"* If yes, write it down.

### What goes where?

**`learnings/browser.md`** (committed — helps all future sessions):
- Bugs or quirks in Aslan itself
- WKWebView/macOS behaviour (ATS, JS eval rules, rendering quirks)
- Patterns for specific site categories (login flows, SERP scraping, SPAs, contenteditable)
- SDK usage patterns that aren't obvious from the reference
- New gotchas not already documented

**`learnings/user.md`** (gitignored — user-specific):
- User's preferred workflows or shortcuts
- Sites the user frequently visits and their quirks
- User preferences (e.g., "always use wait_until=idle", "prefer a11y tree over text")
- Personal context that shouldn't be committed (account patterns, automation preferences)

### How to append a learning:

```bash
cat >> ~/.pi/agent/skills/aslan-browser/learnings/browser.md << 'EOF'

## [Date] — [Topic]
[What you discovered and why it matters]
EOF
```

```bash
cat >> ~/.pi/agent/skills/aslan-browser/learnings/user.md << 'EOF'

## [Date] — [Topic]
[What you discovered and why it matters]
EOF
```

### When to check:

- **After every completed browsing task** — even if nothing went wrong. Smooth patterns are worth recording too.
- **After any error or unexpected behaviour** — especially if you had to retry or work around something.
- **After discovering a site-specific pattern** — login flows, anti-bot measures, SPA quirks, contenteditable inputs.

### What NOT to do:

- DO NOT silently discard a discovery. If it would have saved time, write it down.
- DO NOT duplicate existing learnings. Read the file first — it's in your context from setup.
- DO NOT write vague learnings. Be specific: what happened, what the fix is, and why.

---

## Explicit Negations

DO NOT write raw socket code or paste `rpc()` helpers. Use the SDK.
DO NOT pre-write a full script before running it. Drive step by step.
DO NOT use one bash call per SDK method. Chain related calls in one heredoc.
DO NOT forget `return` in `evaluate` scripts — WKWebView's `callAsyncJavaScript` returns `None` without it.
DO NOT navigate to `http://` URLs — ATS blocks them. Always use `https://`.
DO NOT launch `/Applications/aslan-browser.app` — it may be stale. Launch from DerivedData.
DO NOT skip loading the SDK Reference and learnings at session start.
DO NOT skip the self-improvement check after completing a task.
