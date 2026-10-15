# Phase 8 — Loading Feedback (Status Bar & Go Button)

Add visual feedback so the user knows when a page is loading. Two components: (1) a Firefox-style status bar at the bottom of each browser window that shows loading state and hovered link URLs, and (2) a Go/Stop button next to the address bar that triggers navigation and reflects loading state.

**State file:** `docs/workflows/state/phase-8-plan.json`
**Dependencies:** Phase 7 complete

---

## Context & Motivation

Two usability gaps identified during real-world use:

1. **No visual feedback during navigation.** When the user types a URL and presses Enter, or when an AI agent triggers navigation via JSON-RPC, nothing in the UI indicates that a page is loading. The old page stays on screen until the new one finishes. There is no spinner, no progress bar, no status text. The user has no way to tell if the browser is working or frozen.

2. **No Go button.** The only way to trigger navigation from the address bar is pressing Enter. Every real browser has a Go/Reload button next to the URL field. During loading, this button should become a Stop button (or show a spinner) — providing both a click target and a loading indicator.

### Design

**Status Bar (bottom of window):**
- A thin `NSTextField` (non-editable, no border) anchored to the bottom of the window, below the WKWebView.
- Height: ~20px. Font: system 11pt. Background: window background. Text color: secondary label.
- **States:**
  - **Idle / page loaded:** Hidden (zero height or fully transparent). No wasted vertical space.
  - **Loading:** Shows "Loading [url]..." text. Visible.
  - **Hovering a link:** Shows the link's destination URL (like Firefox/Safari). Visible. *(Stretch goal — implement if time permits; requires JS bridge hook.)*
- The status bar appears/disappears smoothly. No jarring layout shifts.

**Go/Stop Button (right side of address bar):**
- An `NSButton` placed to the right of the URL text field in the top bar area.
- **States:**
  - **Idle:** Shows a "→" (Go arrow) or a reload icon. Clicking triggers navigation to the URL in the address bar (same as pressing Enter).
  - **Loading:** Shows an `NSProgressIndicator` (spinning) or changes to an "✕" (Stop) icon. Clicking calls `webView.stopLoading()`.
- The button is compact (~28x28) and sits flush with the URL field.

**WKWebView hooks used:**
- `webView(_:didStartProvisionalNavigation:)` — fires when navigation begins. Set loading state to true. Show status bar. Switch button to loading/stop.
- `webView(_:didFinish:)` — fires when navigation completes. Set loading state to false. Hide status bar. Switch button to idle/go.
- `webView(_:didFail:)` and `webView(_:didFailProvisionalNavigation:)` — fires on error. Set loading state to false. Hide status bar. Switch button to idle.
- `estimatedProgress` KVO observation (optional, for progress text) — gives 0.0–1.0 loading progress.

---

## Tools

### State Queries

```bash
# Get next pending work item ID
jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-8-plan.json | head -1

# Get full details of a specific work item
jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-8-plan.json

# Get progress summary
jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-8-plan.json
```

### State Mutations

```bash
# Mark item as done
jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-8-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-8-plan.json

# Mark item as error
jq --arg id "ITEM_ID" --arg err "Error description" '(.workItems[] | select(.id == $id)) |= . + {"status": "error", "errorMsg": $err}' docs/workflows/state/phase-8-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-8-plan.json
```

### Build & Verify

```bash
# Compile
xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

# Test via socat (app must be running)
echo '{"jsonrpc":"2.0","id":1,"method":"navigate","params":{"url":"https://example.com"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock

# Quick manual test: navigate to a slow-loading page
echo '{"jsonrpc":"2.0","id":1,"method":"navigate","params":{"url":"https://www.wikipedia.org","waitUntil":"idle"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
```

---

## Workflow

### 1. Setup (One-time)

1. Read configuration:
   ```bash
   jq '.metadata' docs/workflows/state/phase-8-plan.json
   ```
   Store: `projectRoot`, `sourceDir`, `socketPath`, `scheme`.

2. Read in full (parallel reads):
   - `docs/workflows/conventions.md`
   - `docs/workflows/notes.md`

3. Check progress:
   ```bash
   jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-8-plan.json
   ```

4. **Verify Phase 7 is complete:**
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-7-plan.json
   ```

5. Read ALL existing Swift source files in full:
   ```bash
   find aslan-browser -name "*.swift" -not -path "*/.*" | sort
   ```
   Read EVERY file listed. This phase primarily modifies `BrowserTab.swift` but must understand the full architecture.

   CRITICAL: Read the ENTIRE content of each file so it is fully in your context. Do NOT skip any file.

### 2. Process Work Items (Repeat for each)

1. **Find next pending item:**
   ```bash
   jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-8-plan.json | head -1
   ```
   If no pending items remain, go to Completion.

2. **Load work item details:**
   ```bash
   jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-8-plan.json
   ```

3. **Check dependencies.**
   Read the `dependsOn` array. For each dependency, verify its status is `"done"`:
   ```bash
   jq --arg id "DEP_ID" '.workItems[] | select(.id == $id) | .status' docs/workflows/state/phase-8-plan.json
   ```
   If any dependency is not done, skip this item and find the next pending item without unmet dependencies.

4. **Load context:**
   Read ALL files in `filesToModify` and `filesToCreate` (if they already exist) in full.
   CRITICAL: Read the ENTIRE file. Do NOT rely on memory from the setup phase — re-read before modifying.

5. **Implement:**

   Follow the work item's `description` and the detailed implementation guidance below.

   ---

   #### Work Item: `loading-state-tracking`

   **Problem:** BrowserTab has no centralized `isLoading` property that other UI components can observe. The existing `didFinishNavigation` flag is part of the readiness system and not suitable for UI state.

   **Fix:** Add a published loading state property and navigation delegate hooks for start/fail.

   **Implementation in BrowserTab.swift:**

   1. Add a `private(set) var isLoading: Bool = false` property to BrowserTab.

   2. Implement `webView(_:didStartProvisionalNavigation:)` — set `isLoading = true`, call `updateLoadingUI()`.

   3. Modify existing `webView(_:didFinish:)` — add `isLoading = false` and `updateLoadingUI()`.

   4. Modify existing `webView(_:didFail:)` — add `isLoading = false` and `updateLoadingUI()`.

   5. Modify existing `webView(_:didFailProvisionalNavigation:)` — add `isLoading = false` and `updateLoadingUI()`.

   6. Add a stub `private func updateLoadingUI()` that will be filled in by later work items:
      ```swift
      private func updateLoadingUI() {
          // Updated by status-bar and go-button work items
      }
      ```

   7. Also store the URL being loaded so the status bar can display it:
      ```swift
      private var loadingURL: String?
      ```
      Set this in `webView(_:didStartProvisionalNavigation:)` by reading `webView.url?.absoluteString`.

   **CRITICAL:** The `didStartProvisionalNavigation` delegate method must be declared `nonisolated` (like the existing delegate methods) and dispatch to MainActor:
   ```swift
   nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
       Task { @MainActor in
           self.isLoading = true
           self.loadingURL = webView.url?.absoluteString
           self.updateLoadingUI()
       }
   }
   ```

   **DO NOT** change the readiness tracking logic (`resetReadinessState`, `checkIdleAndResume`, etc.). Loading state for UI is separate from the readiness system used by `waitForIdle`.

   ---

   #### Work Item: `status-bar`

   **Problem:** No visual feedback at the bottom of the window indicating loading state.

   **Fix:** Add a non-editable `NSTextField` at the bottom of the container view, below the WKWebView. Show/hide it based on loading state.

   **Implementation in BrowserTab.swift:**

   1. Add a `statusBar` property:
      ```swift
      private var statusBar: NSTextField?
      ```

   2. In `init`, create the status bar and add it to the container view. Modify the existing Auto Layout constraints to accommodate it:

      ```swift
      // Status bar — thin text field at bottom
      let statusBar = NSTextField(labelWithString: "")
      statusBar.font = NSFont.systemFont(ofSize: 11)
      statusBar.textColor = .secondaryLabelColor
      statusBar.backgroundColor = .windowBackgroundColor
      statusBar.drawsBackground = true
      statusBar.isEditable = false
      statusBar.isBezeled = false
      statusBar.lineBreakMode = .byTruncatingMiddle
      statusBar.translatesAutoresizingMaskIntoConstraints = false
      statusBar.isHidden = true  // Hidden by default
      self.statusBar = statusBar

      container.addSubview(statusBar)
      ```

   3. Update the Auto Layout constraints. The current layout is:
      - urlBar pinned to top
      - webView from urlBar.bottom to container.bottom

      Change to:
      - urlBar pinned to top
      - webView from urlBar.bottom to statusBar.top
      - statusBar pinned to bottom

      ```swift
      NSLayoutConstraint.activate([
          // URL bar at top
          urlBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
          urlBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
          urlBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
          urlBar.heightAnchor.constraint(equalToConstant: 28),

          // WebView fills middle
          wv.topAnchor.constraint(equalTo: urlBar.bottomAnchor, constant: 4),
          wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
          wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
          wv.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

          // Status bar at bottom
          statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
          statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
          statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
          statusBar.heightAnchor.constraint(equalToConstant: 20),
      ])
      ```

   4. **CRITICAL: Hidden behavior.** When `statusBar.isHidden = true`, Auto Layout still reserves the 20px height because the height constraint is active. To reclaim that space when hidden, use a **height constraint that changes** instead of `isHidden`:

      Better approach — use a height constraint that toggles:
      ```swift
      private var statusBarHeightConstraint: NSLayoutConstraint?
      ```

      In init:
      ```swift
      let heightConstraint = statusBar.heightAnchor.constraint(equalToConstant: 0)
      self.statusBarHeightConstraint = heightConstraint
      ```

      In the `NSLayoutConstraint.activate` block, use `heightConstraint` instead of the fixed 20pt one.

      Then in `updateLoadingUI()`:
      ```swift
      private func updateLoadingUI() {
          if isLoading {
              statusBar?.stringValue = "Loading \(loadingURL ?? "")…"
              statusBar?.isHidden = false
              statusBarHeightConstraint?.constant = 20
          } else {
              statusBar?.stringValue = ""
              statusBar?.isHidden = true
              statusBarHeightConstraint?.constant = 0
          }
          // Go button state updated here too (added by go-button work item)
      }
      ```

   5. Also update status bar text when navigation finishes with the page title (briefly flash "Done" or just hide):
      On `isLoading = false`, simply hide the bar (set height to 0 and isHidden to true). No "Done" flash — keep it simple.

   **DO NOT** add animation to the show/hide for now. Keep it instant. Animation can be added later if desired.

   **DO NOT** implement link-hover status text in this work item. That is a stretch goal for a future phase (requires JS bridge to report mouseenter/mouseleave on anchor elements).

   ---

   #### Work Item: `go-button`

   **Problem:** No Go button next to the address bar. No visual loading indicator in the toolbar area.

   **Fix:** Add an `NSButton` to the right of the URL text field. In idle state it shows "→" and triggers navigation. In loading state it shows "✕" and stops loading.

   **Implementation in BrowserTab.swift:**

   1. Add properties:
      ```swift
      private var goButton: NSButton?
      ```

   2. In `init`, create the button and add it to the container. Modify the URL bar constraints to make room:

      ```swift
      let goBtn = NSButton(title: "→", target: nil, action: nil)
      goBtn.bezelStyle = .texturedRounded
      goBtn.font = NSFont.systemFont(ofSize: 14)
      goBtn.translatesAutoresizingMaskIntoConstraints = false
      goBtn.widthAnchor.constraint(equalToConstant: 36).isActive = true
      goBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true
      self.goButton = goBtn

      container.addSubview(goBtn)
      ```

      **Important:** The `target` and `action` must be set AFTER `super.init()` (same pattern as urlField):
      ```swift
      // After super.init()
      goBtn.target = self
      goBtn.action = #selector(goButtonAction(_:))
      ```

      Wait — the button is created before `super.init()` but target/action must be set after. Store the button in a local var, add to container, then set target/action after super.init:

      ```swift
      // Before super.init — create the button
      let goBtn = NSButton(title: "→", target: nil, action: nil)
      goBtn.bezelStyle = .texturedRounded
      goBtn.font = NSFont.systemFont(ofSize: 14)
      goBtn.translatesAutoresizingMaskIntoConstraints = false
      self.goButton = goBtn
      container.addSubview(goBtn)

      // ... super.init() ...

      // After super.init — wire target/action
      goBtn.target = self
      goBtn.action = #selector(goButtonAction(_:))
      ```

   3. Update Auto Layout constraints. The URL bar currently stretches from leading+4 to trailing-4. Now the Go button sits at the trailing edge:

      ```swift
      // URL bar: leading+4 to goButton.leading-4
      urlBar.trailingAnchor.constraint(equalTo: goBtn.leadingAnchor, constant: -4),

      // Go button: trailing-4, same vertical as urlBar
      goBtn.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
      goBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
      ```

      Remove the old `urlBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4)`.

   4. Implement the action handler:
      ```swift
      @objc private func goButtonAction(_ sender: NSButton) {
          if isLoading {
              // Stop loading
              webView.stopLoading()
              isLoading = false
              updateLoadingUI()
          } else {
              // Trigger navigation (same as pressing Enter in URL field)
              guard let urlField = urlField else { return }
              urlFieldAction(urlField)
          }
      }
      ```

   5. Update `updateLoadingUI()` to also toggle the button appearance:
      ```swift
      private func updateLoadingUI() {
          if isLoading {
              statusBar?.stringValue = "Loading \(loadingURL ?? "")…"
              statusBar?.isHidden = false
              statusBarHeightConstraint?.constant = 20
              goButton?.title = "✕"
          } else {
              statusBar?.stringValue = ""
              statusBar?.isHidden = true
              statusBarHeightConstraint?.constant = 0
              goButton?.title = "→"
          }
      }
      ```

   **CRITICAL:** The `goButtonAction` method needs `@objc` — which requires `NSObject` inheritance (BrowserTab already inherits from NSObject).

   **CRITICAL:** Do NOT add an `NSProgressIndicator` spinner. A simple text change ("→" ↔ "✕") is sufficient and avoids AppKit layout complexity with embedding a spinner inside a button. KISS.

   **DO NOT** add a separate Reload button. The Go button does not become a Reload button when idle — it stays as Go ("→"). Reload is available via the JSON-RPC `reload` method or Cmd+R (if added in a future phase). YAGNI.

   ---

   #### Work Item: `url-bar-loading-feedback`

   **Problem:** Even with the status bar and go button, the URL field itself gives no feedback. When you press Enter, the text just sits there.

   **Fix:** While loading, change the URL field's text color to a muted/gray tone. When loading completes, restore normal color and update the URL to the final resolved URL.

   **Implementation in BrowserTab.swift:**

   1. In `updateLoadingUI()`, add URL field color feedback:
      ```swift
      private func updateLoadingUI() {
          if isLoading {
              statusBar?.stringValue = "Loading \(loadingURL ?? "")…"
              statusBar?.isHidden = false
              statusBarHeightConstraint?.constant = 20
              goButton?.title = "✕"
              urlField?.textColor = .tertiaryLabelColor
          } else {
              statusBar?.stringValue = ""
              statusBar?.isHidden = true
              statusBarHeightConstraint?.constant = 0
              goButton?.title = "→"
              urlField?.textColor = .textColor
          }
      }
      ```

   2. That's it. The URL field text already gets updated to the final URL in `updateURLField()` which is called from `webView(_:didFinish:)` via `updateWindowTitle()`. The color change during loading is the only addition.

   **DO NOT** add a progress bar inside the URL field (like Chrome's blue loading bar). That requires custom drawing and is out of scope. The text color change is subtle but effective.

   ---

   #### Work Item: `api-navigate-feedback`

   **Problem:** When an AI agent triggers navigation via the JSON-RPC `navigate` method, the status bar and go button should also reflect loading state. Currently the `navigate()` method in BrowserTab calls `webView.load()` which fires the same WKNavigationDelegate callbacks — so this should already work. But we need to verify and ensure the `loadingURL` is set correctly for API-initiated navigation.

   **Fix:** In `BrowserTab.navigate(to:waitUntil:timeout:)`, set `loadingURL` to the target URL BEFORE calling `webView.load()`, and call `updateLoadingUI()` immediately. This ensures the status bar shows the URL even before `didStartProvisionalNavigation` fires (which may have a slight delay).

   **Implementation in BrowserTab.swift:**

   1. In the `navigate()` method, after `resetReadinessState()`, add:
      ```swift
      self.isLoading = true
      self.loadingURL = urlString
      self.updateLoadingUI()
      ```

   2. This applies to all three `waitUntil` cases (`.none`, `.load`, `.idle`).

   **CRITICAL:** The `navigate()` method already calls `resetReadinessState()` at the top. Add the loading UI update right after that, BEFORE the `switch waitUntil` block. This way, no matter which wait mode is used, the UI updates immediately.

   **DO NOT** add loading feedback for `goBack()`, `goForward()`, or `reload()` in this work item — they go through the same WKNavigationDelegate callbacks and will automatically trigger `didStartProvisionalNavigation` → `didFinish`, which already updates loading state via the `loading-state-tracking` work item.

   ---

6. **Verify build:**
   ```bash
   xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   ```
   - If BUILD FAILED: Read the error messages. Fix the issues. Re-verify.
   - If BUILD SUCCEEDED: Continue.

7. **Work-item-specific verification:**

   For `loading-state-tracking`:
   - Build succeeds.
   - Verify `isLoading` property exists and is toggled by all four delegate methods.
   - **Manual test:** Launch app, navigate to a page. Check console logs for any errors.

   For `status-bar`:
   - Build succeeds.
   - **Manual test:** Launch app. Navigate to `https://www.wikipedia.org`. Status bar should appear at bottom showing "Loading https://www.wikipedia.org…". When page finishes loading, status bar should disappear.

   For `go-button`:
   - Build succeeds.
   - **Manual test:** Launch app. The "→" button should be visible to the right of the URL field. Type a URL and click the button — page should navigate. During loading, button should show "✕". Click "✕" — loading should stop.

   For `url-bar-loading-feedback`:
   - Build succeeds.
   - **Manual test:** Navigate to a page. URL text should turn gray during loading, then return to normal color when done.

   For `api-navigate-feedback`:
   - Build succeeds.
   - **Manual test:** With app running, send a navigation command via socat:
     ```bash
     echo '{"jsonrpc":"2.0","id":1,"method":"navigate","params":{"url":"https://www.wikipedia.org","waitUntil":"idle"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
     ```
     Observe the browser window — status bar should appear, go button should show "✕", URL text should be gray. All should reset when page finishes.

8. **Update state:**
   ```bash
   jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-8-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-8-plan.json
   ```

9. **Update notes:**
   Add any discoveries, edge cases, or gotchas to `docs/workflows/notes.md`.

10. **Return to step 1.**

### 3. Completion

1. Show final progress:
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-8-plan.json
   ```

2. Verify the complete phase:
   - All work items have status `"done"`.
   - App builds cleanly.
   - Status bar appears during navigation and hides when done (manual test).
   - Go button shows "→" when idle, "✕" when loading (manual test).
   - Clicking Go triggers navigation (manual test).
   - Clicking Stop (✕) halts loading (manual test).
   - URL field text grays out during loading (manual test).
   - JSON-RPC `navigate` also triggers visual feedback (manual test).
   - No regressions: Cmd+V still works, address bar Enter still works, window close still works.

3. Rebuild Release binary:
   ```bash
   xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Release build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   ```

4. Add to `notes.md`:
   ```
   ## Phase 8 — Loading Feedback

   **Status:** Complete ✅

   ### Changes
   - Loading state tracking via isLoading property and WKNavigationDelegate hooks
   - Firefox-style status bar at bottom of window (appears during loading, shows URL)
   - Go/Stop button next to URL field ("→" idle, "✕" loading)
   - URL field text grays out during loading
   - API-initiated navigation (JSON-RPC) also triggers all visual feedback
   ```

5. **Commit all changes** (see conventions.md §8):
   ```bash
   git add -A
   git status  # verify no junk files
   git commit -m "Phase 8: Loading feedback — status bar and Go button

   - Add isLoading state tracking with WKNavigationDelegate hooks
   - Add Firefox-style status bar at bottom showing loading URL
   - Add Go/Stop button next to address bar (→ idle, ✕ loading)
   - Gray out URL field text during loading
   - All feedback works for both manual and API-initiated navigation"
   ```

6. Update `docs/workflows/README.md` to include Phase 8 in the phase table.
