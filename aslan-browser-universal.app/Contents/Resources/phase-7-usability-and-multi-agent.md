# Phase 7 — Usability & Multi-Agent

Fix keyboard shortcuts (Cmd+V paste), add window controls (close/minimize), add an address bar for manual navigation, introduce session-based tab ownership for multi-agent scenarios, and add batch operations so a single agent can read from multiple tabs in one round-trip.

**State file:** `docs/workflows/state/phase-7-plan.json`
**Dependencies:** Phase 6 complete

---

## Context & Motivation

Six issues identified during real-world use:

1. **Cmd+V doesn't work in password fields.** User must right-click → Paste. Root cause: nib-less AppKit app has no Edit menu, so standard keyboard shortcuts (Cmd+C/V/X/A/Z) are never wired to the responder chain. WKWebView handles paste internally — but only when the menu item fires the `paste:` action through the responder chain. No menu = no shortcut.

2. **No address bar.** The browser was built for AI agents, but there are valid use cases where a human navigates to a page first, then tells the agent "look at this page." Currently the user must tell the agent the URL, the agent navigates, then reads — an unnecessary round-trip. A URL bar saves one step.

3. **Traffic light buttons (close/minimize/maximize) are disabled.** The NSWindow style mask is `[.titled, .resizable]` — it's missing `.closable` and `.miniaturizable`. The red/yellow dots render but do nothing. Users can't close or minimize browser windows.

4. **No visual tab identification.** Tabs exist via the JSON-RPC API (`tab.create`, `tab.list`, `tab.close`), but each tab is a separate NSWindow with no title indicating which tab it is. Multiple windows are indistinguishable.

5. **No multi-agent tab ownership.** If two agents connect to the same aslan-browser instance, they see each other's tabs. There's no mechanism to say "these tabs belong to agent A" and "those tabs belong to agent B." Agents can accidentally close or interact with each other's tabs.

6. **No parallel tab reads.** An agent can open multiple tabs, but must read each one sequentially (one JSON-RPC call at a time). For research workflows — open 5 pages, read all accessibility trees — this is slow. A batch operation would let one agent fetch all trees in a single round-trip.

---

## Tools

### State Queries

```bash
# Get next pending work item ID
jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-7-plan.json | head -1

# Get full details of a specific work item
jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-7-plan.json

# Get progress summary
jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-7-plan.json
```

### State Mutations

```bash
# Mark item as done
jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-7-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-7-plan.json

# Mark item as error
jq --arg id "ITEM_ID" --arg err "Error description" '(.workItems[] | select(.id == $id)) |= . + {"status": "error", "errorMsg": $err}' docs/workflows/state/phase-7-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-7-plan.json
```

### Build & Verify

```bash
# Compile
xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

# Test via socat (app must be running)
echo '{"jsonrpc":"2.0","id":1,"method":"tab.list","params":{}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock

# Test batch method
echo '{"jsonrpc":"2.0","id":1,"method":"batch","params":{"requests":[{"method":"getTitle","params":{"tabId":"tab0"}},{"method":"getURL","params":{"tabId":"tab0"}}]}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock

# Test session
echo '{"jsonrpc":"2.0","id":1,"method":"session.create","params":{}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock

# Run integration tests
python3 tests/test_socket.py
cd sdk/python && python3 -m pytest tests/ -v
```

---

## Workflow

### 1. Setup (One-time)

1. Read configuration:
   ```bash
   jq '.metadata' docs/workflows/state/phase-7-plan.json
   ```
   Store: `projectRoot`, `sourceDir`, `socketPath`, `scheme`.

2. Read in full (parallel reads):
   - `docs/workflows/conventions.md`
   - `docs/workflows/notes.md`

3. Check progress:
   ```bash
   jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-7-plan.json
   ```

4. **Verify Phase 6 is complete:**
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-6-plan.json
   ```

5. Read ALL existing Swift source files in full:
   ```bash
   find aslan-browser -name "*.swift" -not -path "*/.*" | sort
   ```
   Read EVERY file. This phase touches AppDelegate, BrowserTab, TabManager, MethodRouter, SocketServer, JSONRPCHandler, and creates new files.

   CRITICAL: Read the ENTIRE content of each file so it is fully in your context. Do NOT skip any file.

6. Read the Python SDK files in full:
   - `sdk/python/aslan_browser/__init__.py`
   - `sdk/python/aslan_browser/client.py`
   - `sdk/python/aslan_browser/async_client.py`

### 2. Process Work Items (Repeat for each)

1. **Find next pending item:**
   ```bash
   jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-7-plan.json | head -1
   ```
   If no pending items remain, go to Completion.

2. **Load work item details:**
   ```bash
   jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-7-plan.json
   ```

3. **Check dependencies.**
   Read the `dependsOn` array. For each dependency, verify its status is `"done"`:
   ```bash
   jq --arg id "DEP_ID" '.workItems[] | select(.id == $id) | .status' docs/workflows/state/phase-7-plan.json
   ```
   If any dependency is not done, skip this item and find the next pending item without unmet dependencies.

4. **Load context:**
   Read ALL files in `filesToModify` and `filesToCreate` (if they already exist) in full.
   CRITICAL: Read the ENTIRE file. Do NOT rely on memory from the setup phase — re-read before modifying.

5. **Implement:**

   Follow the work item's `description` and the detailed implementation guidance below.

   ---

   #### Work Item: `edit-menu`

   **Problem:** Nib-less AppKit app has no main menu. Without an Edit menu, the standard keyboard shortcuts (Cmd+C, Cmd+V, Cmd+X, Cmd+A, Cmd+Z) are never processed by AppKit's responder chain. WKWebView supports paste, copy, cut — but only when the corresponding `paste:`, `copy:`, `cut:` Objective-C actions are dispatched through the menu system.

   **Fix:** Create a programmatic main menu in `AppDelegate.applicationDidFinishLaunching` (or a dedicated `setupMainMenu()` method called from it). The menu must be set BEFORE any windows are created, so the responder chain is ready.

   **Implementation — add to AppDelegate.swift:**

   ```swift
   private func setupMainMenu() {
       let mainMenu = NSMenu()

       // ── App menu ──
       let appMenuItem = NSMenuItem()
       mainMenu.addItem(appMenuItem)
       let appMenu = NSMenu()
       appMenu.addItem(NSMenuItem(title: "About Aslan Browser", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
       appMenu.addItem(NSMenuItem.separator())
       appMenu.addItem(NSMenuItem(title: "Quit Aslan Browser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
       appMenuItem.submenu = appMenu

       // ── Edit menu ──
       let editMenuItem = NSMenuItem()
       mainMenu.addItem(editMenuItem)
       let editMenu = NSMenu(title: "Edit")
       editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
       editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
       editMenu.addItem(NSMenuItem.separator())
       editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
       editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
       editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
       editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
       editMenuItem.submenu = editMenu

       NSApp.mainMenu = mainMenu
   }
   ```

   Call `setupMainMenu()` as the FIRST thing in `applicationDidFinishLaunching`, before `TabManager` creation or anything else.

   **Why this fixes Cmd+V in password fields:** When a user presses Cmd+V, AppKit looks for a menu item with key equivalent `"v"` + command modifier. It finds the Paste item, which sends `paste:` up the responder chain. WKWebView's internal responder handles `paste:` and inserts clipboard content into the focused field. Without the menu item, the keystroke is never translated into a `paste:` action.

   **CRITICAL:** The `Selector(("undo:"))` syntax (double parentheses) is required for `undo:` and `redo:` because they are Objective-C selectors not exposed as Swift `#selector` targets. `cut:`, `copy:`, `paste:`, `selectAll:` work with `#selector` on `NSText`.

   **DO NOT** add File, View, or Window menus. Keep it minimal — only what's needed for keyboard shortcuts to work.

   ---

   #### Work Item: `window-controls`

   **Problem:** NSWindow style mask is `[.titled, .resizable]`. Missing `.closable` and `.miniaturizable` makes the red/yellow traffic light buttons inert. Window title is empty, so multiple tab windows are indistinguishable.

   **Fix in BrowserTab.swift:**

   1. Change the style mask to `[.titled, .closable, .miniaturizable, .resizable]`.

   2. Set the window title to `"{tabId} — {url_or_blank}"`. Example: `"tab0 — https://example.com"`.

   3. Make BrowserTab conform to `NSWindowDelegate` and set `window.delegate = self`.

   4. Implement `windowShouldClose(_:)` to handle the close button:
      - Post a notification or call a callback so TabManager can remove the tab from its map.
      - Call `cleanup()` on the BrowserTab.
      - Return `true` to allow the close.

   5. Update window title on navigation completion (in `webView(_:didFinish:)`).

   **Implementation details:**

   ```swift
   // In BrowserTab.init:
   let win = NSWindow(
       contentRect: frame,
       styleMask: [.titled, .closable, .miniaturizable, .resizable],
       backing: .buffered,
       defer: false
   )
   win.title = tabId
   ```

   ```swift
   // BrowserTab conforms to NSWindowDelegate
   // Add after super.init():
   win.delegate = self
   ```

   ```swift
   // Add a callback for window close notification
   var onWindowClose: ((_ tabId: String) -> Void)?

   nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
       Task { @MainActor in
           self.onWindowClose?(self.tabId)
       }
       return false  // TabManager will handle actual close via closeTab()
   }
   ```

   Returning `false` from `windowShouldClose` prevents the window from closing itself. Instead, the callback tells TabManager to run its full `closeTab()` flow (which handles animation cleanup and deferred deallocation). This avoids the use-after-free crash discovered in Phase 5.

   **In TabManager** — when creating a tab, wire up the callback:
   ```swift
   tab.onWindowClose = { [weak self] tabId in
       try? self?.closeTab(id: tabId)
   }
   ```

   **Window title updates** — add a `updateWindowTitle()` method to BrowserTab:
   ```swift
   func updateWindowTitle() {
       let url = webView.url?.absoluteString ?? ""
       let title = webView.title ?? ""
       let display = title.isEmpty ? url : title
       window.title = display.isEmpty ? tabId : "\(tabId) — \(display)"
   }
   ```
   Call this in `webView(_:didFinish:)` after the navigation completes, and also after `navigate()` returns when `waitUntil` is `.idle`.

   ---

   #### Work Item: `address-bar`

   **Problem:** No way for a human to navigate manually. The user has to ask the AI agent to go to a URL, which is one unnecessary step when the user already knows the URL.

   **Fix:** Add an `NSTextField` above the `WKWebView` in each tab's window. The text field shows the current URL. Pressing Enter navigates to the typed URL.

   **Implementation in BrowserTab.swift:**

   Replace the current layout (where `webView` is the entire `contentView`) with a container that has the URL bar on top and the webView below.

   ```swift
   // Create URL bar
   let urlField = NSTextField()
   urlField.placeholderString = "Enter URL..."
   urlField.font = NSFont.systemFont(ofSize: 13)
   urlField.bezelStyle = .roundedBezel
   urlField.translatesAutoresizingMaskIntoConstraints = false
   urlField.target = self
   urlField.action = #selector(urlFieldAction(_:))
   self.urlField = urlField  // Store as property

   // Container with Auto Layout
   let container = NSView(frame: frame)
   container.translatesAutoresizingMaskIntoConstraints = false
   wv.translatesAutoresizingMaskIntoConstraints = false

   container.addSubview(urlField)
   container.addSubview(wv)
   win.contentView = container

   NSLayoutConstraint.activate([
       urlField.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
       urlField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
       urlField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
       urlField.heightAnchor.constraint(equalToConstant: 28),

       wv.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 4),
       wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
       wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
       wv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
   ])
   ```

   **Handle Enter key:**
   ```swift
   @objc private func urlFieldAction(_ sender: NSTextField) {
       var urlString = sender.stringValue.trimmingCharacters(in: .whitespaces)
       if urlString.isEmpty { return }

       // Add https:// if no scheme provided
       if !urlString.contains("://") {
           urlString = "https://" + urlString
       }

       Task { @MainActor in
           do {
               let result = try await self.navigate(to: urlString)
               sender.stringValue = result.url
           } catch {
               NSLog("[aslan-browser] URL bar navigation failed: \(error)")
           }
       }
   }
   ```

   **Update URL field on navigation** — add to `updateWindowTitle()` or add a separate `updateURLField()` call in `webView(_:didFinish:)`:
   ```swift
   func updateURLField() {
       urlField?.stringValue = webView.url?.absoluteString ?? ""
   }
   ```

   **CRITICAL:** The `@objc` on `urlFieldAction` requires BrowserTab to inherit from `NSObject` (which it already does). The `target`/`action` pattern is standard AppKit for text field submission.

   **CRITICAL:** The container `NSView` frame must NOT use `translatesAutoresizingMaskIntoConstraints = false` when it IS the window's `contentView`. The window's content view is managed by NSWindow. Only the subviews inside it should use Auto Layout constraints. Set `container.translatesAutoresizingMaskIntoConstraints = true` (the default) and use the `frame` passed to `NSWindow`. The subviews (urlField, webView) use `translatesAutoresizingMaskIntoConstraints = false`.

   Actually, the cleanest pattern: create a plain `NSView` as the container with the same frame, set it as `contentView`, then add constraints for the subviews relative to the container:

   ```swift
   let container = NSView(frame: frame)
   // container keeps translatesAutoresizingMaskIntoConstraints = true (default)
   // because NSWindow manages contentView sizing
   win.contentView = container

   urlField.translatesAutoresizingMaskIntoConstraints = false
   wv.translatesAutoresizingMaskIntoConstraints = false
   container.addSubview(urlField)
   container.addSubview(wv)

   NSLayoutConstraint.activate([
       urlField.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
       urlField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
       urlField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
       urlField.heightAnchor.constraint(equalToConstant: 28),

       wv.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 4),
       wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
       wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
       wv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
   ])
   ```

   ---

   #### Work Item: `tab-sessions`

   **Problem:** When two agents connect to the same aslan-browser instance, they share the same tab namespace. Agent A sees Agent B's tabs. Agent A could accidentally close Agent B's tabs. There's no isolation.

   **Solution:** Introduce lightweight sessions. A session is just a string label that tags tabs with ownership. Sessions are optional — backward-compatible with existing sessionless usage.

   **New JSON-RPC methods:**

   | Method | Params | Returns | Notes |
   |---|---|---|---|
   | `session.create` | `{name?}` | `{sessionId}` | Auto-generated ID: `"s0"`, `"s1"`, etc. Optional human-readable name. |
   | `session.destroy` | `{sessionId}` | `{ok, closedTabs: [...]}` | Closes all tabs owned by this session. |

   **Modified methods:**

   | Method | Change |
   |---|---|
   | `tab.create` | Accepts optional `sessionId` param. If provided, the new tab is tagged with this session. |
   | `tab.list` | Accepts optional `sessionId` param. If provided, returns only tabs belonging to this session. If omitted, returns all tabs (backward-compatible). |

   **Implementation:**

   Add `sessionId: String?` property to `BrowserTab`.

   Add session tracking to `TabManager`:
   ```swift
   struct Session {
       let sessionId: String
       let name: String
   }

   private var sessions: [String: Session] = [:]
   private var nextSessionId: Int = 0

   func createSession(name: String? = nil) -> String {
       let sessionId = "s\(nextSessionId)"
       nextSessionId += 1
       sessions[sessionId] = Session(sessionId: sessionId, name: name ?? sessionId)
       return sessionId
   }

   func destroySession(id: String) throws -> [String] {
       guard sessions.removeValue(forKey: id) != nil else {
           throw BrowserError.sessionNotFound(id)
       }
       // Find and close all tabs with this sessionId
       let tabIds = tabs.filter { $0.value.sessionId == id }.map { $0.key }
       for tabId in tabIds {
           try closeTab(id: tabId)
       }
       return tabIds
   }
   ```

   Modify `createTab()` to accept optional `sessionId`:
   ```swift
   @discardableResult
   func createTab(width: Int = 1440, height: Int = 900, hidden: Bool? = nil, sessionId: String? = nil) -> String {
       // ... existing code ...
       tab.sessionId = sessionId
       // ...
   }
   ```

   Modify `listTabs()` to accept optional session filter:
   ```swift
   func listTabs(sessionId: String? = nil) -> [TabInfo] {
       let filtered = sessionId == nil ? tabs : tabs.filter { $0.value.sessionId == sessionId }
       return filtered.map { ... }.sorted { $0.tabId < $1.tabId }
   }
   ```

   Add `sessionNotFound` case to `BrowserError` enum with a new JSON-RPC error code `-32004`.

   Add `session.create` and `session.destroy` handlers to `MethodRouter`.

   **The default tab0 has no session** — it belongs to everyone (backward-compatible).

   **Design decision: sessions are NOT tied to socket connections.** A session persists until explicitly destroyed. Multiple connections can share a session if they know the sessionId. This is intentional — an agent might reconnect and resume its session.

   ---

   #### Work Item: `batch-operations`

   **Problem:** An agent researching a topic opens 5 tabs and needs all their accessibility trees. Currently this requires 5 sequential JSON-RPC calls — one per tab. Each call has socket round-trip overhead.

   **Solution:** Add a `batch` JSON-RPC method that accepts multiple sub-requests and returns all results in one response. Sub-requests execute concurrently via Swift `TaskGroup`.

   **New JSON-RPC method:**

   | Method | Params | Returns | Notes |
   |---|---|---|---|
   | `batch` | `{requests: [{method, params}, ...]}` | `{responses: [{result} \| {error}, ...]}` | Executes all requests concurrently. Results returned in same order as requests. |

   **Request format:**
   ```json
   {
     "jsonrpc": "2.0",
     "id": 1,
     "method": "batch",
     "params": {
       "requests": [
         {"method": "getAccessibilityTree", "params": {"tabId": "tab1"}},
         {"method": "getAccessibilityTree", "params": {"tabId": "tab2"}},
         {"method": "getAccessibilityTree", "params": {"tabId": "tab3"}}
       ]
     }
   }
   ```

   **Response format:**
   ```json
   {
     "jsonrpc": "2.0",
     "id": 1,
     "result": {
       "responses": [
         {"result": {"tree": [...]}},
         {"result": {"tree": [...]}},
         {"error": {"code": -32000, "message": "Tab not found: tab3"}}
       ]
     }
   }
   ```

   **Implementation in MethodRouter:**

   ```swift
   private func handleBatch(_ params: [String: Any]?) async throws -> [String: Any] {
       guard let requests = params?["requests"] as? [[String: Any]] else {
           throw RPCError.invalidParams("Missing required param: requests (array)")
       }

       // Execute all sub-requests concurrently
       let responses = await withTaskGroup(of: (Int, [String: Any]).self) { group in
           for (index, req) in requests.enumerated() {
               group.addTask {
                   guard let method = req["method"] as? String else {
                       return (index, ["error": ["code": -32600, "message": "Missing method in batch request"]])
                   }
                   let subParams = req["params"] as? [String: Any]
                   do {
                       let result = try await self.dispatch(method, params: subParams)
                       return (index, ["result": result])
                   } catch let err as RPCError {
                       return (index, ["error": ["code": err.code, "message": err.message]])
                   } catch let err as BrowserError {
                       let rpcErr = err.rpcError
                       return (index, ["error": ["code": rpcErr.code, "message": rpcErr.message]])
                   } catch {
                       return (index, ["error": ["code": -32603, "message": error.localizedDescription]])
                   }
               }
           }

           var results = [(Int, [String: Any])]()
           for await result in group {
               results.append(result)
           }
           // Sort by original index to preserve order
           return results.sorted { $0.0 < $1.0 }.map { $0.1 }
       }

       return ["responses": responses]
   }
   ```

   **CRITICAL:** The `batch` method must NOT allow recursive batches — if a sub-request method is `"batch"`, return an error for that sub-request. Add a guard:
   ```swift
   if method == "batch" {
       return (index, ["error": ["code": -32600, "message": "Nested batch not allowed"]])
   }
   ```

   **CRITICAL:** The `dispatch` method is `@MainActor`. All sub-tasks in the TaskGroup also run on `@MainActor` because BrowserTab operations require MainActor. The concurrency here is structural (TaskGroup manages suspension points) but actual WKWebView calls are serialized per tab. Cross-tab operations (different tabs) will interleave at await points.

   ---

   #### Work Item: `sdk-updates`

   **Update Python SDK** to support the new methods.

   **Add to `client.py` (AslanBrowser):**

   ```python
   # ── sessions ──────────────────────────────────────────────────────

   def session_create(self, name: Optional[str] = None) -> str:
       """Create a new session. Returns the session ID."""
       params: dict[str, Any] = {}
       if name:
           params["name"] = name
       result = self._call("session.create", params)
       return result["sessionId"]

   def session_destroy(self, session_id: str) -> list[str]:
       """Destroy a session and close all its tabs. Returns closed tab IDs."""
       result = self._call("session.destroy", {"sessionId": session_id})
       return result.get("closedTabs", [])

   # ── batch operations ──────────────────────────────────────────────

   def batch(self, requests: list[dict]) -> list[dict]:
       """Execute multiple requests in one round-trip.

       Args:
           requests: List of {"method": ..., "params": ...} dicts.

       Returns:
           List of {"result": ...} or {"error": ...} dicts, in same order.
       """
       result = self._call("batch", {"requests": requests})
       return result.get("responses", [])

   def parallel_get_trees(self, tab_ids: list[str]) -> dict[str, list[dict]]:
       """Get accessibility trees from multiple tabs in one call.

       Returns:
           Dict mapping tab_id → tree (list of A11yNode dicts).
           If a tab errored, its value is an empty list.
       """
       requests = [
           {"method": "getAccessibilityTree", "params": {"tabId": tid}}
           for tid in tab_ids
       ]
       responses = self.batch(requests)
       result = {}
       for tid, resp in zip(tab_ids, responses):
           if "result" in resp:
               result[tid] = resp["result"].get("tree", [])
           else:
               result[tid] = []
       return result

   def parallel_navigate(
       self,
       urls: dict[str, str],
       wait_until: str = "load",
   ) -> dict[str, dict]:
       """Navigate multiple tabs to different URLs in one call.

       Args:
           urls: Dict mapping tab_id → URL.
           wait_until: "load", "idle", or "none".

       Returns:
           Dict mapping tab_id → {"url": ..., "title": ...} or {"error": ...}.
       """
       requests = [
           {"method": "navigate", "params": {"tabId": tid, "url": url, "waitUntil": wait_until}}
           for tid, url in urls.items()
       ]
       responses = self.batch(requests)
       result = {}
       for (tid, _), resp in zip(urls.items(), responses):
           if "result" in resp:
               result[tid] = resp["result"]
           else:
               result[tid] = resp.get("error", {"message": "Unknown error"})
       return result

   def parallel_screenshots(
       self, tab_ids: list[str], quality: int = 70, width: int = 1440
   ) -> dict[str, bytes]:
       """Take screenshots of multiple tabs in one call.

       Returns:
           Dict mapping tab_id → JPEG bytes. Errored tabs omitted.
       """
       requests = [
           {"method": "screenshot", "params": {"tabId": tid, "quality": quality, "width": width}}
           for tid in tab_ids
       ]
       responses = self.batch(requests)
       result = {}
       for tid, resp in zip(tab_ids, responses):
           if "result" in resp and "data" in resp["result"]:
               result[tid] = base64.b64decode(resp["result"]["data"])
       return result
   ```

   **Update `tab_create`** to accept optional `session_id`:
   ```python
   def tab_create(
       self,
       url: Optional[str] = None,
       width: int = 1440,
       height: int = 900,
       hidden: Optional[bool] = None,
       session_id: Optional[str] = None,
   ) -> str:
       params: dict[str, Any] = {"width": width, "height": height}
       if url:
           params["url"] = url
       if hidden is not None:
           params["hidden"] = hidden
       if session_id:
           params["sessionId"] = session_id
       result = self._call("tab.create", params)
       return result["tabId"]
   ```

   **Update `tab_list`** to accept optional `session_id`:
   ```python
   def tab_list(self, session_id: Optional[str] = None) -> list[dict]:
       params: dict[str, Any] = {}
       if session_id:
           params["sessionId"] = session_id
       result = self._call("tab.list", params)
       return result.get("tabs", [])
   ```

   **Mirror all changes to `async_client.py` (AsyncAslanBrowser).** Same methods, same signatures, but `async def` and `await self._call(...)`.

   **Update `__init__.py`** exports if needed (should already export both clients).

   ---

   #### Work Item: `integration-tests`

   **Create or update integration tests** to cover all Phase 7 features.

   Test file: `tests/test_phase7.py` (new file, separate from existing tests).

   **Tests to write:**

   1. **test_paste_shortcut** — This cannot be automated via JSON-RPC (it's a native keyboard shortcut). Instead, add a manual test note in the test file docstring. Verify manually that Cmd+V works in a password field after the edit-menu fix.

   2. **test_window_close_callback** — Create a tab, verify it appears in `tab.list`, then close its window programmatically (not via JSON-RPC). Verify it disappears from `tab.list`. Since we can't click the close button via JSON-RPC, test `tab.close` and verify proper cleanup.

   3. **test_address_bar_navigation** — Cannot be automated from the outside. Document as manual test.

   4. **test_session_create_destroy** — Create a session, create tabs in it, verify `tab.list` with session filter, destroy session, verify tabs are gone.
      ```python
      def test_session_lifecycle(browser):
          sid = browser.session_create(name="test-agent")
          t1 = browser.tab_create(url="https://example.com", session_id=sid)
          t2 = browser.tab_create(url="https://example.org", session_id=sid)

          # List with session filter
          session_tabs = browser.tab_list(session_id=sid)
          assert len(session_tabs) == 2

          # List without filter should include all tabs (tab0 + t1 + t2)
          all_tabs = browser.tab_list()
          assert len(all_tabs) >= 3

          # Destroy session
          closed = browser.session_destroy(sid)
          assert set(closed) == {t1, t2}

          # Tabs are gone
          remaining = browser.tab_list()
          assert t1 not in [t["tabId"] for t in remaining]
          assert t2 not in [t["tabId"] for t in remaining]
      ```

   5. **test_batch_operations** — Create tabs, navigate, batch read trees.
      ```python
      def test_batch_get_trees(browser):
          t1 = browser.tab_create(url="https://example.com")
          t2 = browser.tab_create(url="https://example.org")
          import time; time.sleep(2)  # Wait for pages to load

          trees = browser.parallel_get_trees([t1, t2])
          assert t1 in trees
          assert t2 in trees
          assert len(trees[t1]) > 0
          assert len(trees[t2]) > 0

          # Cleanup
          browser.tab_close(t1)
          browser.tab_close(t2)
      ```

   6. **test_batch_error_handling** — Batch request with one valid and one invalid tab.
      ```python
      def test_batch_partial_error(browser):
          responses = browser.batch([
              {"method": "getTitle", "params": {"tabId": "tab0"}},
              {"method": "getTitle", "params": {"tabId": "nonexistent"}},
          ])
          assert "result" in responses[0]
          assert "error" in responses[1]
      ```

   7. **test_window_title** — Navigate to a page and verify the window title could be checked via getTitle (indirect verification).

   **Use pytest.** Each test function should be self-contained. Use a `browser` fixture that creates a fresh `AslanBrowser` connection.

6. **Verify build:**
   ```bash
   xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   ```
   - If BUILD FAILED: Read the error messages. Fix the issues. Re-verify.
   - If BUILD SUCCEEDED: Continue.

   For Python-only work items (`sdk-updates`, `integration-tests`): verify with:
   ```bash
   cd sdk/python && python3 -c "from aslan_browser import AslanBrowser; print('Import OK')"
   ```

7. **Work-item-specific verification:**

   For `edit-menu`:
   - Build succeeds.
   - Verify `NSApp.mainMenu` is set by adding a temporary `NSLog("[aslan-browser] Main menu set with \(NSApp.mainMenu?.items.count ?? 0) items")` after `setupMainMenu()`.
   - **Manual test:** Launch app, navigate to a login page (e.g., Gmail), click the password field, press Cmd+V. It should paste.

   For `window-controls`:
   - Build succeeds.
   - **Manual test:** Launch app. Red close button should be active (clickable). Yellow minimize button should be active. Clicking close should remove the tab from `tab.list`.
   - Verify window title shows tab info via:
     ```bash
     echo '{"jsonrpc":"2.0","id":1,"method":"navigate","params":{"url":"https://example.com"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
     ```
     Window title should update to something like `"tab0 — Example Domain"`.

   For `address-bar`:
   - Build succeeds.
   - **Manual test:** Launch app. URL bar should be visible at the top of the browser window. Type `example.com` and press Enter. Page should navigate. URL bar should update to show `https://example.com/`.

   For `tab-sessions`:
   - Build succeeds.
   - Test via socat:
     ```bash
     echo '{"jsonrpc":"2.0","id":1,"method":"session.create","params":{"name":"agent-1"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
     ```
     Should return `{"jsonrpc":"2.0","id":1,"result":{"sessionId":"s0"}}`.

   For `batch-operations`:
   - Build succeeds.
   - Test via socat:
     ```bash
     echo '{"jsonrpc":"2.0","id":1,"method":"batch","params":{"requests":[{"method":"getTitle","params":{"tabId":"tab0"}},{"method":"getURL","params":{"tabId":"tab0"}}]}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
     ```
     Should return both results.

   For `sdk-updates`:
   - `python3 -c "from aslan_browser import AslanBrowser; b = AslanBrowser.__new__(AslanBrowser); print([m for m in dir(b) if not m.startswith('_')])"` — verify new methods are present.

   For `integration-tests`:
   - Start aslan-browser, then:
     ```bash
     python3 tests/test_phase7.py
     ```
     Or with pytest:
     ```bash
     cd sdk/python && python3 -m pytest tests/ -v -k "phase7 or session or batch"
     ```

8. **Update state:**
   ```bash
   jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-7-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-7-plan.json
   ```

9. **Update notes:**
   Add any discoveries, edge cases, or gotchas to `docs/workflows/notes.md`.

10. **Return to step 1.**

### 3. Completion

1. Show final progress:
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-7-plan.json
   ```

2. Verify the complete phase:
   - All work items have status `"done"`.
   - App builds cleanly.
   - Cmd+V works in password fields (manual test).
   - Close button works on browser windows (manual test).
   - Address bar navigates on Enter (manual test).
   - Sessions create/destroy correctly (automated test).
   - Batch operations return concurrent results (automated test).
   - Python SDK has all new methods.
   - Integration tests pass.

3. Rebuild and install the Release binary:
   ```bash
   xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Release build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   ```
   If the app was installed to `/Applications/`, update with the new build.

4. Add to `notes.md`:
   ```
   ## Phase 7 — Usability & Multi-Agent

   **Status:** Complete ✅

   ### Changes
   - Edit menu added (Cmd+C/V/X/A/Z now work in WKWebView fields)
   - Window controls: close, minimize, window titles showing tab + page info
   - Address bar for manual URL entry
   - Session-based tab ownership for multi-agent isolation
   - Batch JSON-RPC method for parallel operations
   - Python SDK: session_create, session_destroy, batch, parallel_get_trees, parallel_navigate, parallel_screenshots
   ```

5. **Commit all changes** (see conventions.md §8):
   ```bash
   git add -A
   git status  # verify no junk files (.profraw, .sync-conflict-*, etc.)
   git commit -m "Phase 7: Usability improvements and multi-agent support

   - Add macOS Edit menu for Cmd+C/V/X keyboard shortcuts
   - Add closable/minimizable window controls with proper tab cleanup
   - Add address bar for manual URL navigation
   - Add session-based tab ownership (session.create, session.destroy)
   - Add batch JSON-RPC method for parallel multi-tab operations
   - Update Python SDK with session, batch, and parallel helper methods
   - Integration tests for sessions and batch operations"
   ```

6. Update `docs/workflows/README.md` to include Phase 7 in the phase table.
