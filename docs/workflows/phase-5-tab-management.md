# Phase 5 — Tab Management + Events

Multi-tab support, server→client event notifications, cookies, and navigation history. At the end of this phase, the full API surface is complete — agents can manage multiple tabs, receive events, and use the complete browser automation API.

**State file:** `docs/workflows/state/phase-5-plan.json`
**Dependencies:** Phase 4 complete

---

## Tools

### State Queries

```bash
# Get next pending work item ID
jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-5-plan.json | head -1

# Get full details of a specific work item
jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-5-plan.json

# Get progress summary
jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-5-plan.json
```

### State Mutations

```bash
# Mark item as done
jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-5-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-5-plan.json

# Mark item as error
jq --arg id "ITEM_ID" --arg err "Error description" '(.workItems[] | select(.id == $id)) |= . + {"status": "error", "errorMsg": $err}' docs/workflows/state/phase-5-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-5-plan.json
```

### Build & Verify

```bash
# Compile
xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

# Test tab management (app must be running)
echo '{"jsonrpc":"2.0","id":1,"method":"tab.create","params":{"url":"https://example.com"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
echo '{"jsonrpc":"2.0","id":2,"method":"tab.list","params":{}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
echo '{"jsonrpc":"2.0","id":3,"method":"tab.close","params":{"tabId":"tab1"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
```

---

## Workflow

### 1. Setup (One-time)

1. Read configuration:
   ```bash
   jq '.metadata' docs/workflows/state/phase-5-plan.json
   ```

2. Read in full (parallel reads):
   - `docs/workflows/conventions.md`
   - `docs/workflows/notes.md`

3. Check progress:
   ```bash
   jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-5-plan.json
   ```

4. **Verify Phase 4 is complete:**
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-4-plan.json
   ```

5. Read all existing source files in full:
   ```bash
   find aslan-browser -name "*.swift" -not -path "*/.*"
   ```
   Read EVERY file. This phase modifies the most files — AppDelegate, MethodRouter, BrowserTab, SocketServer, ScriptBridge, and creates TabManager.

### 2. Process Work Items (Repeat for each)

1. **Find next pending item:**
   ```bash
   jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-5-plan.json | head -1
   ```
   If no pending items remain, go to Completion.

2. **Load work item details:**
   ```bash
   jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-5-plan.json
   ```

3. **Check dependencies.**

4. **Load context:**
   Read ALL files in `filesToModify` and `filesToCreate` (if they already exist) in full.
   CRITICAL: The `tab-manager` work item touches many files. Read ALL of them before starting.

5. **Implement:**

   **CRITICAL constraints for this phase:**
   - TabManager is `@MainActor` (same as BrowserTab — it manages BrowserTab instances).
   - Tab IDs are auto-generated: `"tab0"`, `"tab1"`, `"tab2"`, etc. Use an incrementing counter.
   - A default tab (`"tab0"`) is created on app launch.
   - ALL existing JSON-RPC methods that previously operated on the single BrowserTab must now accept `tabId` in params and resolve through TabManager.
   - `tab.close` must clean up: close NSWindow, remove from TabManager map, release WKWebView.
   - Do NOT close the default tab. Or if closed, allow it — but TabManager should handle empty state gracefully.
   - Event notifications are JSON-RPC messages without an `id` field (per conventions.md).
   - Events are sent to ALL connected clients, not just the one that created the tab.
   - Cookie operations MUST await completion before returning. This is a race condition source.

   **TabManager design:**
   ```swift
   @MainActor
   class TabManager {
       private var tabs: [String: BrowserTab] = [:]
       private var nextId: Int = 0
       
       func createTab(url: URL?, width: Int, height: Int, hidden: Bool) async -> String
       func closeTab(id: String) throws
       func getTab(id: String) throws -> BrowserTab
       func listTabs() -> [TabInfo]
   }
   ```

   **Event notification format:**
   ```json
   {"jsonrpc":"2.0","method":"event.console","params":{"tabId":"tab0","level":"log","message":"hello world"}}
   {"jsonrpc":"2.0","method":"event.navigation","params":{"tabId":"tab0","url":"https://example.com"}}
   {"jsonrpc":"2.0","method":"event.error","params":{"tabId":"tab0","message":"ReferenceError: x is not defined","source":"https://example.com","line":42}}
   ```

   **Console capture approach:**
   Override console methods in ScriptBridge JS:
   ```javascript
   ['log', 'warn', 'error', 'info'].forEach(level => {
       const original = console[level];
       console[level] = function(...args) {
           window.webkit.messageHandlers.agent.postMessage({
               type: 'console',
               level: level,
               message: args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' ')
           });
           original.apply(console, args);
       };
   });
   ```

   **Decision framework for event delivery:**
   - SocketServer must track all connected client channels.
   - BrowserTab produces events via a callback/delegate pattern to TabManager.
   - TabManager forwards events to SocketServer.
   - SocketServer writes JSON-RPC notification to all connected channels.
   - If a channel write fails (client disconnected), remove the channel. Do NOT crash.

   **Cookie handling:**
   ```swift
   func getCookies(url: URL?) async -> [[String: Any]] {
       let store = webView.configuration.websiteDataStore.httpCookieStore
       let cookies = await store.allCookies()
       // Filter by url if provided
       // Return as array of dicts
   }
   
   func setCookie(_ cookie: HTTPCookie) async {
       let store = webView.configuration.websiteDataStore.httpCookieStore
       await store.setCookie(cookie)
       // MUST await — do not return before cookie is set
   }
   ```

6. **Verify build:**
   ```bash
   xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   ```

7. **Work-item-specific verification:**

   For `tab-manager`:
   - Verify TabManager.swift and TabInfo.swift exist.
   - Verify AppDelegate uses TabManager.
   - Verify MethodRouter resolves tabId for all methods.
   - Verify default tab0 is created on launch.

   For `tab-methods`:
   - Test tab creation and listing:
     ```bash
     echo '{"jsonrpc":"2.0","id":1,"method":"tab.create","params":{"url":"https://example.com"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
     echo '{"jsonrpc":"2.0","id":2,"method":"tab.list","params":{}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
     ```

   For `event-notifications`:
   - Verify console override in ScriptBridge JS.
   - Verify SocketServer tracks client channels.
   - Verify notifications are written to clients.

   For `cookies`:
   - Verify getCookies and setCookie async methods.
   - Verify setCookie awaits completion.

   For `navigation-history`:
   - Verify goBack/goForward/reload methods.
   - Verify they wait for navigation to complete.

   For `integration-test-v2`:
   - Run updated integration test:
     ```bash
     python3 tests/test_socket.py
     ```

8. **Update state:**
   ```bash
   jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-5-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-5-plan.json
   ```

9. **Update notes.**

10. **Return to step 1.**

### 3. Completion

1. Show final progress:
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-5-plan.json
   ```

2. Verify the complete phase — the full Swift API surface is now done:
   - Tab management: create, close, list
   - Navigation: navigate (with waitUntil), goBack, goForward, reload, waitForSelector
   - Interaction: click, fill, select, keypress, scroll
   - Extraction: getAccessibilityTree, getHTML, getTitle, getURL, screenshot
   - State: getCookies, setCookie
   - Events: console, navigation, error notifications

3. Summarize and add to `notes.md`: "Phase 5 complete. Full API surface operational. Ready for Python SDK."

4. **Commit all changes** (see conventions.md §8):
   ```bash
   git add -A
   git status  # verify no junk files
   git commit -m "Phase 5: Tab management and full API surface"
   ```
