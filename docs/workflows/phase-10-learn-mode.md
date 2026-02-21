# Phase 10 — Learn Mode (Record & Playbook Generation)

Add a recording mode that captures user actions in the browser so an AI agent can generate site-specific playbooks automatically — eliminating the trial-and-error loop that currently costs hundreds of tokens per new site.

**State file:** `docs/workflows/state/phase-10-plan.json`
**Dependencies:** Phase 9 complete

---

## Context & Motivation

The agent's existing playbooks (`knowledge/playbooks/linkedin-create-post.md`, `instagram-create-post.md`, `gmb-create-post.md`) were hand-compiled through painful trial and error. For each new site, the agent:

1. Navigates to the page
2. Screenshots → sends to LLM (expensive — vision tokens)
3. Tries to interact → fails (wrong selector, shadow DOM, contenteditable)
4. Screenshots again → tries another approach
5. Repeats 5-20 times until the task succeeds
6. Manually writes the playbook

The `reddit.com.md` site knowledge — shadow DOM paths, `composedPath()` patterns, flair modal workarounds — was discovered through this exact grind.

**Learn Mode** inverts this: the user demonstrates the task once, the browser records everything (with full shadow DOM path resolution via `event.composedPath()`), and the agent generates the playbook from the recording. What used to take 20+ agent turns now takes one human demonstration.

### What Gets Built

| Component | What |
|---|---|
| `LearnRecorder.swift` | Global recording state machine, action storage, screenshot capture, temp directory management |
| `ScriptBridge.swift` additions | Learn-mode JS event listeners (click, input, keydown, scroll) with `composedPath()` shadow DOM tracing |
| `BrowserTab.swift` additions | Script message routing for learn actions, inject/remove learn JS, recording UI (● REC indicator + Add Note button with system symbol), navigation event capture during recording |
| `TabManager.swift` additions | Owns LearnRecorder, propagates start/stop to all tabs, auto-injects on new tab creation, logs tab lifecycle events |
| `MethodRouter.swift` additions | Four new JSON-RPC methods: `learn.start`, `learn.stop`, `learn.status`, `learn.note` |
| `BrowserError.swift` additions | `learnModeError` case + RPC code `-32005` |
| `RPCMessage.swift` additions | `RPCError.learnModeError()` factory |
| Python SDK + CLI | `learn_start()`, `learn_stop()`, `learn_status()` methods + `aslan learn start/stop/status` commands |
| Skill docs | Updated SKILL.md and SDK_REFERENCE.md with learn mode workflow |

---

## Design

### Recording Flow

```
Agent calls learn.start("reddit-create-post")
    │
    ├── LearnRecorder: state = .recording, create /tmp/aslan-learn/reddit-create-post/
    ├── TabManager: inject learn-mode JS into ALL open tabs
    ├── BrowserTab (each): show ● REC indicator + Add Note button
    │
    ▼
User performs task in browser
    │
    ├── User clicks  → JS captures composedPath + element info → posts learn.action
    ├── User types   → JS captures input value + target → posts learn.action
    ├── User presses key → JS captures key + modifiers → posts learn.action
    ├── User scrolls → JS captures scroll position → posts learn.action
    ├── Page navigates → BrowserTab.didFinish → logs navigation action
    ├── User clicks Add Note → NSAlert with NSTextView → logs annotation
    │
    ▼
Agent calls learn.stop
    │
    ├── TabManager: remove learn-mode JS from all tabs
    ├── BrowserTab (each): hide ● REC + Add Note button
    ├── LearnRecorder: state = .idle, return full action log
    │
    ▼
Agent reads action log → generates playbook → saves to knowledge/playbooks/
```

### Action Log Format

Each recording produces an ordered array of actions. Screenshots are saved to disk (not inline base64). The log references file paths.

```json
{
  "name": "reddit-create-post",
  "startedAt": 1708502400000,
  "duration": 45000,
  "actionCount": 12,
  "screenshotDir": "/tmp/aslan-learn/reddit-create-post",
  "actions": [
    {
      "seq": 1,
      "type": "navigation",
      "timestamp": 1708502400100,
      "tabId": "tab0",
      "url": "https://www.reddit.com/r/ClaudeCode/submit",
      "pageTitle": "Submit to r/ClaudeCode",
      "screenshot": "/tmp/aslan-learn/reddit-create-post/step-001.jpg"
    },
    {
      "seq": 2,
      "type": "click",
      "timestamp": 1708502403000,
      "tabId": "tab0",
      "url": "https://www.reddit.com/r/ClaudeCode/submit",
      "pageTitle": "Submit to r/ClaudeCode",
      "target": {
        "tagName": "BUTTON",
        "textContent": "Switch to Markdown",
        "attributes": {"class": "switch-btn", "type": "button"},
        "composedPath": [
          "HTML > BODY > SHREDDIT-APP",
          "#shadow-root > DIV.container > SHREDDIT-COMPOSER",
          "#shadow-root > BUTTON.switch-btn"
        ],
        "rect": {"x": 450, "y": 320, "w": 160, "h": 36}
      },
      "screenshot": "/tmp/aslan-learn/reddit-create-post/step-002.jpg"
    },
    {
      "seq": 3,
      "type": "input",
      "timestamp": 1708502410000,
      "tabId": "tab0",
      "url": "https://www.reddit.com/r/ClaudeCode/submit",
      "pageTitle": "Submit to r/ClaudeCode",
      "target": {
        "tagName": "TEXTAREA",
        "textContent": "",
        "attributes": {"placeholder": "Body text (optional)"},
        "composedPath": [
          "HTML > BODY > SHREDDIT-APP",
          "#shadow-root > SHREDDIT-COMPOSER",
          "#shadow-root > FACEPLATE-TEXTAREA-INPUT",
          "#shadow-root > TEXTAREA"
        ],
        "rect": {"x": 200, "y": 400, "w": 600, "h": 200}
      },
      "value": "Hello, this is my post content...",
      "screenshot": "/tmp/aslan-learn/reddit-create-post/step-003.jpg"
    },
    {
      "seq": 4,
      "type": "annotation",
      "timestamp": 1708502415000,
      "text": "The flair modal button requires a full pointer event sequence to submit — regular click() doesn't work."
    }
  ]
}
```

### Target Element Identification

The key technical innovation: **`event.composedPath()`** traces through shadow DOM boundaries at event time. No guessing, no trial-and-error.

For each user action, the JS listener calls `composedPath()` and builds:

- **`composedPath`** — array of strings, each representing one shadow boundary level. Format: `"TAG.class#id > TAG.class > ..."` with `"#shadow-root > ..."` at each shadow boundary.
- **`tagName`** — immediate target's tag name
- **`textContent`** — target's text (truncated to 80 chars, whitespace-collapsed)
- **`attributes`** — relevant attributes: `id`, `class`, `name`, `type`, `role`, `aria-label`, `data-testid`, `placeholder`, `href`, `src`, `action`, `value`
- **`rect`** — bounding client rect `{x, y, w, h}`

### Screenshots

Taken ~500ms after each user action (to let the page react — modals opening, dropdowns expanding, navigation completing). Saved as JPEG to the session's temp directory.

The sequence of post-action screenshots tells the visual story: screenshot N shows the page state after action N (which is the state before action N+1).

**Storage:** Each recording session gets its own directory: `/tmp/aslan-learn/{name}/`. On `learn.start`, if the directory exists, it is deleted and recreated. Screenshots are ephemeral — they exist for the agent to read during playbook generation, then can be discarded.

### Recording UI

When recording is active, two elements appear in the toolbar next to the Go/Stop button:

```
[URL bar                     ] [→/✕] ● REC [🗒]
                                      ▲       ▲
                                      │       └── Add Note (NSButton with SF Symbol)
                                      └── Red "● REC" label (NSTextField, non-interactive)
```

- **● REC indicator:** `NSTextField(labelWithString: "● REC")` with red text color. Non-editable, non-interactive. Just a visual signal.
- **Add Note button:** `NSButton` with SF Symbol image (`NSImage(systemSymbolName: "note.text", accessibilityDescription: "Add Note")`). Clicking opens an `NSAlert` with:
  - Message: "Add Annotation"
  - Accessory view: `NSTextView` inside `NSScrollView` (multi-line text area, ~260×80)
  - Buttons: "Add" + "Cancel"
  - On "Add": sends the text to LearnRecorder as an annotation action

Both elements are hidden by default. Shown when LearnRecorder signals recording started, hidden when stopped. Every BrowserTab shows them (recording is global across all tabs).

### JSON-RPC Methods

| Method | Params | Returns | Error Cases |
|---|---|---|---|
| `learn.start` | `{"name": "reddit-create-post"}` | `{"ok": true, "name": "reddit-create-post", "screenshotDir": "/tmp/aslan-learn/reddit-create-post"}` | Already recording → `-32005` |
| `learn.stop` | none | `{"name": "...", "duration": 45000, "actionCount": 12, "screenshotDir": "...", "actions": [...]}` | Not recording → `-32005` |
| `learn.status` | none | `{"recording": true/false, "name": "..." or null, "actionCount": 0}` | — |
| `learn.note` | `{"text": "..."}` | `{"ok": true, "seq": 4}` | Not recording → `-32005` |

### CLI Commands

```bash
aslan learn start <name>     # Start recording. Prints: "Recording: <name>"
aslan learn stop             # Stop recording. Prints: action summary (count, duration)
aslan learn status           # Prints: "Recording: <name> (N actions)" or "Not recording"
```

`learn stop` outputs a summary, not the full action log. The full log is retrieved via the JSON-RPC response (the SDK returns it). For CLI, the agent uses `--json` to get the full response if needed:

```bash
aslan learn stop --json      # Full action log as JSON
```

---

## Tools

### State Queries

```bash
# Get next pending work item ID
jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-10-plan.json | head -1

# Get full details of a specific work item
jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-10-plan.json

# Get progress summary
jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-10-plan.json
```

### State Mutations

```bash
# Mark item as done
jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-10-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-10-plan.json

# Mark item as error
jq --arg id "ITEM_ID" --arg err "Error description" '(.workItems[] | select(.id == $id)) |= . + {"status": "error", "errorMsg": $err}' docs/workflows/state/phase-10-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-10-plan.json
```

### Build & Verify

```bash
# Compile
xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

# Quick RPC test (app must be running)
echo '{"jsonrpc":"2.0","id":1,"method":"learn.status","params":{}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock

# Start recording
echo '{"jsonrpc":"2.0","id":1,"method":"learn.start","params":{"name":"test-recording"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock

# Check recording status
echo '{"jsonrpc":"2.0","id":1,"method":"learn.status","params":{}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock

# Stop recording and get log
echo '{"jsonrpc":"2.0","id":1,"method":"learn.stop","params":{}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock

# Verify temp directory
ls -la /tmp/aslan-learn/test-recording/
```

---

## Workflow

### 1. Setup (One-time)

1. Read configuration:
   ```bash
   jq '.metadata' docs/workflows/state/phase-10-plan.json
   ```
   Store: `projectRoot`, `sourceDir`, `socketPath`, `scheme`, `sdkDir`, `skillDir`.

2. Read in full (parallel reads):
   - `docs/workflows/conventions.md`
   - `docs/workflows/notes.md`

3. Check progress:
   ```bash
   jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-10-plan.json
   ```

4. **Verify Phase 9 is complete:**
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-9-plan.json
   ```

5. Read ALL Swift source files in full:
   ```bash
   find aslan-browser -name "*.swift" -not -path "*/.*" -not -name "*.sync-conflict-*" | sort
   ```
   Read EVERY file listed. This phase touches most of them.

   CRITICAL: Read the ENTIRE content of each file so it is fully in your context. Do NOT skip any file.

6. Read the existing skill files (parallel reads):
   - `skills/aslan-browser/SKILL.md`
   - `skills/aslan-browser/SDK_REFERENCE.md`
   - `skills/aslan-browser/knowledge/core.md`

7. Read one existing playbook to understand the target output format:
   - `skills/aslan-browser/knowledge/playbooks/linkedin-create-post.md`

### 2. Process Work Items (Repeat for each)

1. **Find next pending item:**
   ```bash
   jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-10-plan.json | head -1
   ```
   If no pending items remain, go to Completion.

2. **Load work item details:**
   ```bash
   jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-10-plan.json
   ```

3. **Check dependencies.**
   Read the `dependsOn` array. For each dependency, verify its status is `"done"`:
   ```bash
   jq --arg id "DEP_ID" '.workItems[] | select(.id == $id) | .status' docs/workflows/state/phase-10-plan.json
   ```
   If any dependency is not done, skip this item and find the next pending item without unmet dependencies.

4. **Load context:**
   Read ALL files in `filesToModify` and `filesToCreate` (if they already exist) in full.
   CRITICAL: Read the ENTIRE file. Do NOT rely on memory from the setup phase — re-read before modifying.

5. **Implement:**

   Follow the work item's `description` and the detailed implementation guidance below.

   ---

   #### Work Item: `learn-recorder-model`

   **Goal:** Create the core data model and state machine for recording. No UI, no JS, no RPC wiring — just the recorder itself.

   **Create `aslan-browser/LearnRecorder.swift`:**

   ```swift
   @MainActor
   class LearnRecorder {
       enum State { case idle, recording }

       private(set) var state: State = .idle
       private(set) var name: String?
       private(set) var actions: [[String: Any]] = []
       private(set) var startTimestamp: Date?
       private var nextSeq: Int = 1
       private var screenshotDir: String?
   ```

   **State machine:**
   - `idle` → `start(name:)` → `recording`
   - `recording` → `stop()` → `idle` (returns action log)
   - `recording` → `addAction(...)` (appends to actions array)
   - `recording` → `addAnnotation(text:)` (appends annotation to actions array)
   - Calling `start()` while recording → throw `BrowserError.learnModeError("Already recording")`
   - Calling `stop()` while idle → throw `BrowserError.learnModeError("Not recording")`
   - Calling `addAction()`/`addAnnotation()` while idle → silently ignore (defensive)

   **`start(name:)` method:**
   1. Set state to `.recording`
   2. Store `name`, `startTimestamp = Date()`
   3. Reset `actions = []`, `nextSeq = 1`
   4. Create temp directory: `/tmp/aslan-learn/{name}/`
      - If directory exists, delete it first (`FileManager.default.removeItem`)
      - Create fresh (`FileManager.default.createDirectory(withIntermediateDirectories: true)`)
   5. Store `screenshotDir` path
   6. Return the screenshotDir path

   **`stop()` method:**
   1. Set state to `.idle`
   2. Calculate duration: `Date().timeIntervalSince(startTimestamp) * 1000` (ms)
   3. Build result dictionary:
      ```swift
      [
          "name": name,
          "startedAt": startTimestamp.timeIntervalSince1970 * 1000,
          "duration": duration,
          "actionCount": actions.count,
          "screenshotDir": screenshotDir,
          "actions": actions
      ]
      ```
   4. Clear `name`, `startTimestamp`, `screenshotDir`
   5. Return the result dictionary

   **`addAction(_ action: [String: Any], screenshotData: String?, tabId: String)` method:**
   1. Guard `state == .recording`, else return
   2. Build action dict: merge incoming action with `seq`, `timestamp`, `tabId`
   3. If `screenshotData` (base64 JPEG) is provided:
      - Write to `{screenshotDir}/step-{seq:03d}.jpg` (decode base64 → Data → write to file)
      - Add `"screenshot": "{path}"` to action dict
      - Writing screenshot file should happen off main thread via `Task.detached`
   4. Append to `actions` array
   5. Increment `nextSeq`
   6. Return `seq`

   **`addAnnotation(text:)` method:**
   1. Guard `state == .recording`, else return
   2. Build annotation dict:
      ```swift
      ["seq": nextSeq, "type": "annotation", "timestamp": Date().timeIntervalSince1970 * 1000, "text": text]
      ```
   3. Append to `actions` array
   4. Increment `nextSeq`
   5. Return `seq`

   **`status()` method:**
   Return `["recording": state == .recording, "name": name as Any, "actionCount": actions.count]`

   **File write helper (private):**
   ```swift
   private func writeScreenshot(base64: String, to path: String) {
       Task.detached {
           guard let data = Data(base64Encoded: base64) else { return }
           try? data.write(to: URL(fileURLWithPath: path))
       }
   }
   ```

   **Also update `aslan-browser/Models/BrowserError.swift`:**
   Add case:
   ```swift
   case learnModeError(String)
   ```
   Add to `rpcError` switch:
   ```swift
   case .learnModeError(let detail):
       return .learnModeError(detail)
   ```

   **Also update `aslan-browser/Models/RPCMessage.swift`:**
   Add to `RPCError`:
   ```swift
   static func learnModeError(_ detail: String) -> RPCError {
       RPCError(code: -32005, message: "Learn mode error", data: detail)
   }
   ```

   **Verification:**
   - Build succeeds
   - LearnRecorder compiles with no warnings
   - BrowserError and RPCError have the new case/factory

   ---

   #### Work Item: `learn-js-listeners`

   **Goal:** Add learn-mode JavaScript to ScriptBridge. This JS is NOT part of the always-injected user script — it is injected on-demand via `evaluateJavaScript()` when recording starts, and removed when recording stops.

   **Add to `aslan-browser/ScriptBridge.swift`:**

   Two new static properties: `learnModeJS` and `learnModeCleanupJS`.

   **`learnModeJS`** — The recording event listeners:

   The JS must:
   1. Guard against double-injection: `if (window.__agentLearn) return;`
   2. Create namespace: `window.__agentLearn = {}`
   3. Define `buildTargetInfo(event)` function that:
      - Calls `event.composedPath()` to get the full path through shadow boundaries
      - Builds `composedPath` array of strings — one string per shadow boundary level
      - Extracts target element info: `tagName`, `textContent` (truncated 80 chars, whitespace-collapsed), `rect` (getBoundingClientRect), key `attributes`
      - Attributes to capture: `id`, `class`, `name`, `type`, `role`, `aria-label`, `aria-labelledby`, `data-testid`, `placeholder`, `href`, `src`, `action`, `value`, `contenteditable`
      - Returns the target info object
   4. Define `buildComposedPath(event)` function that:
      - Iterates `event.composedPath()`
      - Groups nodes by shadow boundary — each time a `ShadowRoot` node is encountered, start a new segment
      - For each segment, build a string like `"TAG.className#id > TAG.className > ..."`
      - Prefix shadow root segments with `"#shadow-root > ..."`
      - Returns array of segment strings
   5. Register event listeners (all on `document`, `capture: true`, `passive: true`):
      - **click**: Post `learn.action` with type `"click"`, target info, `clientX`/`clientY`, `button`
      - **input**: Post `learn.action` with type `"input"`, target info, `event.target.value` (for input/textarea/select) or `event.target.textContent` (for contenteditable). Use debounce (300ms) — input events fire on every keystroke; only capture the final value after a pause.
      - **keydown**: Post `learn.action` with type `"keydown"`, target info, `key`, `code`, modifier booleans (`ctrlKey`, `shiftKey`, `altKey`, `metaKey`). Filter: only capture Enter, Tab, Escape, Backspace, Delete, and modified keys (Ctrl/Cmd+anything). Do NOT capture regular character keystrokes — those are covered by the input event.
      - **scroll**: Post `learn.action` with type `"scroll"`, `scrollX: window.scrollX`, `scrollY: window.scrollY`. Use debounce (500ms) — scroll events fire continuously; only capture the final position after scrolling stops.
   6. Store all listener references on `window.__agentLearn` so cleanup can remove them

   **Posting actions:**
   ```javascript
   window.__agent.post("learn.action", {
       type: "click",
       url: window.location.href,
       pageTitle: document.title,
       target: buildTargetInfo(event),
       clientX: event.clientX,
       clientY: event.clientY,
       button: event.button
   });
   ```

   **Input debouncing pattern:**
   ```javascript
   var inputTimer = null;
   function onInput(event) {
       if (inputTimer) clearTimeout(inputTimer);
       inputTimer = setTimeout(function() {
           var val = event.target.value !== undefined ? event.target.value : (event.target.textContent || "");
           window.__agent.post("learn.action", {
               type: "input",
               url: window.location.href,
               pageTitle: document.title,
               target: buildTargetInfo(event),
               value: val
           });
       }, 300);
   }
   ```

   **`learnModeCleanupJS`** — Removes all listeners:
   ```javascript
   (function() {
       if (!window.__agentLearn) return;
       document.removeEventListener("click", window.__agentLearn.onClick, true);
       document.removeEventListener("input", window.__agentLearn.onInput, true);
       document.removeEventListener("keydown", window.__agentLearn.onKeydown, true);
       document.removeEventListener("scroll", window.__agentLearn.onScroll, true);
       delete window.__agentLearn;
   })();
   ```

   **CRITICAL:** All listeners use `{capture: true, passive: true}`. They MUST NOT call `event.preventDefault()` or `event.stopPropagation()`. They are passive observers only.

   **CRITICAL:** The `composedPath()` call must happen synchronously inside the event handler. The composed path is only available during event dispatch — if you defer it to a setTimeout/Promise, it will be empty.

   **CRITICAL:** For the debounced `input` event handler, capture the target info synchronously (inside the event handler, before the debounce timeout), but defer the posting. This is because `event.composedPath()` is only available during dispatch, but we want to debounce the actual message. Store the captured info in a closure variable.

   **DO NOT** add the learn JS to `ScriptBridge.injectedJS` (the always-injected user script). It must be a separate static property that BrowserTab injects on-demand via `webView.evaluateJavaScript()`.

   **Verification:**
   - Build succeeds
   - `ScriptBridge.learnModeJS` and `ScriptBridge.learnModeCleanupJS` compile

   ---

   #### Work Item: `learn-browser-tab-wiring`

   **Goal:** Wire BrowserTab to receive `learn.action` script messages, take post-action screenshots, and forward everything to LearnRecorder. Also add methods to inject/remove learn JS, and capture navigation events during recording.

   **Implementation in `BrowserTab.swift`:**

   1. Add a `learnRecorder` property (weak reference — owned by TabManager):
      ```swift
      weak var learnRecorder: LearnRecorder?
      ```

   2. In `handleScriptMessage(_ body:)`, add a new case:
      ```swift
      case "learn.action":
          guard let recorder = learnRecorder, recorder.state == .recording else { break }
          // Extract action data from dict (everything except "type")
          var actionData = dict
          actionData.removeValue(forKey: "type")
          // Take screenshot after a brief delay (let page react)
          Task { @MainActor in
              try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
              let base64 = try? await self.screenshot(quality: 60, width: 1440)
              let _ = recorder.addAction(actionData, screenshotData: base64, tabId: self.tabId)
          }
      ```

   3. Add methods to inject/remove learn-mode JS:
      ```swift
      func startLearnMode() {
          webView.evaluateJavaScript(ScriptBridge.learnModeJS, completionHandler: nil)
      }

      func stopLearnMode() {
          webView.evaluateJavaScript(ScriptBridge.learnModeCleanupJS, completionHandler: nil)
      }
      ```

   4. In the existing `webView(_:didFinish:)` delegate method, add navigation event logging during recording:
      ```swift
      // After existing code, before the closing brace:
      if let recorder = self.learnRecorder, recorder.state == .recording {
          let navAction: [String: Any] = [
              "type": "navigation",
              "url": url,
              "pageTitle": title
          ]
          Task { @MainActor in
              try? await Task.sleep(nanoseconds: 500_000_000) // 500ms for page to settle
              let base64 = try? await self.screenshot(quality: 60, width: 1440)
              let _ = recorder.addAction(navAction, screenshotData: base64, tabId: self.tabId)
          }
          // Re-inject learn listeners on new page (navigation clears JS state)
          self.startLearnMode()
      }
      ```

   5. **CRITICAL:** After every navigation (`didFinish`), the injected learn-mode JS is wiped because the page reloaded. Must re-inject `startLearnMode()` if recording is active. This is done in step 4 above.

   6. **CRITICAL:** The `screenshot()` call inside the learn action handler uses lower quality (60) to keep files small. Learn-mode screenshots are for context during playbook generation, not for vision model analysis.

   **DO NOT** modify `handleScriptMessage` for any message types other than `learn.action`. Existing message types (`domStable`, `networkIdle`, etc.) remain unchanged.

   **Verification:**
   - Build succeeds
   - BrowserTab has `learnRecorder`, `startLearnMode()`, `stopLearnMode()`
   - `handleScriptMessage` routes `learn.action` type

   ---

   #### Work Item: `learn-tab-manager-wiring`

   **Goal:** TabManager owns the LearnRecorder and coordinates recording across all tabs.

   **Implementation in `TabManager.swift`:**

   1. Add the LearnRecorder as a property:
      ```swift
      let learnRecorder = LearnRecorder()
      ```

   2. In `createTab()`, after setting `tab.onEvent` and `tab.onWindowClose`, set the recorder:
      ```swift
      tab.learnRecorder = learnRecorder
      ```

   3. In `createTab()`, if recording is active, auto-inject learn JS into the new tab:
      ```swift
      if learnRecorder.state == .recording {
          tab.startLearnMode()
      }
      ```

   4. Add methods to start/stop recording across all tabs:
      ```swift
      func startLearnMode(name: String) throws -> [String: Any] {
          let screenshotDir = try learnRecorder.start(name: name)
          // Inject learn JS into all existing tabs
          for tab in tabs.values {
              tab.startLearnMode()
          }
          return ["ok": true, "name": name, "screenshotDir": screenshotDir]
      }

      func stopLearnMode() throws -> [String: Any] {
          let result = try learnRecorder.stop()
          // Remove learn JS from all existing tabs
          for tab in tabs.values {
              tab.stopLearnMode()
          }
          return result
      }
      ```

   5. In `createTab()`, if recording is active, log a `tab.created` action:
      ```swift
      if learnRecorder.state == .recording {
          let _ = learnRecorder.addAction(
              ["type": "tab.created", "url": "", "pageTitle": ""],
              screenshotData: nil,
              tabId: tabId
          )
          tab.startLearnMode()
      }
      ```

   6. In `closeTab()`, if recording is active, log a `tab.closed` action:
      ```swift
      if learnRecorder.state == .recording {
          let url = tab.webView.url?.absoluteString ?? ""
          let title = tab.webView.title ?? ""
          let _ = learnRecorder.addAction(
              ["type": "tab.closed", "url": url, "pageTitle": title],
              screenshotData: nil,
              tabId: id
          )
      }
      ```

   **DO NOT** make LearnRecorder optional. It is always created with TabManager. Its `.idle` state is the "off" state.

   **Verification:**
   - Build succeeds
   - TabManager creates LearnRecorder
   - All tabs get `learnRecorder` reference on creation
   - `startLearnMode`/`stopLearnMode` propagate to all tabs

   ---

   #### Work Item: `learn-rpc-methods`

   **Goal:** Wire the four JSON-RPC methods in MethodRouter.

   **Implementation in `MethodRouter.swift`:**

   1. Add cases to `dispatch()`:
      ```swift
      case "learn.start":
          return try handleLearnStart(params)
      case "learn.stop":
          return try handleLearnStop(params)
      case "learn.status":
          return handleLearnStatus(params)
      case "learn.note":
          return try handleLearnNote(params)
      ```

   2. Implement handlers:
      ```swift
      private func handleLearnStart(_ params: [String: Any]?) throws -> [String: Any] {
          guard let name = params?["name"] as? String else {
              throw RPCError.invalidParams("Missing required param: name")
          }
          return try tabManager.startLearnMode(name: name)
      }

      private func handleLearnStop(_ params: [String: Any]?) throws -> [String: Any] {
          return try tabManager.stopLearnMode()
      }

      private func handleLearnStatus(_ params: [String: Any]?) -> [String: Any] {
          return tabManager.learnRecorder.status()
      }

      private func handleLearnNote(_ params: [String: Any]?) throws -> [String: Any] {
          guard let text = params?["text"] as? String else {
              throw RPCError.invalidParams("Missing required param: text")
          }
          guard tabManager.learnRecorder.state == .recording else {
              throw BrowserError.learnModeError("Not recording")
          }
          let seq = tabManager.learnRecorder.addAnnotation(text: text)
          return ["ok": true, "seq": seq as Any]
      }
      ```

   3. Note: `handleLearnStart` and `handleLearnStop` are NOT `async` — they call synchronous TabManager methods. The screenshot-taking happens asynchronously inside LearnRecorder but doesn't block the RPC response.

   **CRITICAL:** `handleLearnStart` throws `RPCError.invalidParams` for missing name, but `tabManager.startLearnMode()` throws `BrowserError.learnModeError` for already-recording. Both are caught by the existing error handling in `JSONRPCHandler`.

   **Verification:**
   - Build succeeds
   - All four methods compile
   - Test via socat:
     ```bash
     echo '{"jsonrpc":"2.0","id":1,"method":"learn.status","params":{}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
     ```
     Should return `{"recording": false, "name": null, "actionCount": 0}`

   ---

   #### Work Item: `learn-recording-ui`

   **Goal:** Add visual recording indicator and annotation button to BrowserTab's toolbar.

   **Implementation in `BrowserTab.swift`:**

   1. Add UI properties:
      ```swift
      private var recLabel: NSTextField?
      private var addNoteButton: NSButton?
      ```

   2. In `init()`, create the recording UI elements (before `super.init()`):

      **REC label:**
      ```swift
      let recLabel = NSTextField(labelWithString: "● REC")
      recLabel.font = NSFont.boldSystemFont(ofSize: 11)
      recLabel.textColor = .systemRed
      recLabel.isEditable = false
      recLabel.isBezeled = false
      recLabel.drawsBackground = false
      recLabel.translatesAutoresizingMaskIntoConstraints = false
      recLabel.isHidden = true
      self.recLabel = recLabel
      container.addSubview(recLabel)
      ```

      **Add Note button:**
      ```swift
      let noteBtn = NSButton(frame: .zero)
      noteBtn.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Add Note")
      noteBtn.bezelStyle = .texturedRounded
      noteBtn.isBordered = true
      noteBtn.translatesAutoresizingMaskIntoConstraints = false
      noteBtn.isHidden = true
      self.addNoteButton = noteBtn
      container.addSubview(noteBtn)
      ```

      Wire target/action after `super.init()`:
      ```swift
      noteBtn.target = self
      noteBtn.action = #selector(addNoteAction(_:))
      ```

   3. Update Auto Layout constraints. The elements go after the Go button:
      ```swift
      // After existing goBtn constraints, add:
      recLabel.centerYAnchor.constraint(equalTo: goBtn.centerYAnchor),
      recLabel.leadingAnchor.constraint(equalTo: goBtn.trailingAnchor, constant: 8),

      noteBtn.centerYAnchor.constraint(equalTo: goBtn.centerYAnchor),
      noteBtn.leadingAnchor.constraint(equalTo: recLabel.trailingAnchor, constant: 4),
      noteBtn.widthAnchor.constraint(equalToConstant: 28),
      noteBtn.heightAnchor.constraint(equalToConstant: 28),
      ```

      **CRITICAL:** The URL bar trailing constraint is currently pinned to goBtn.leading. This does NOT need to change — the REC label and note button are to the RIGHT of the Go button, outside the URL bar's constraint chain. The Go button remains pinned to trailing-4. The REC label and note button extend beyond the Go button. This means the window needs to be wide enough — but at 1440px default, there is ample room.

      Wait — the Go button is pinned to `container.trailingAnchor - 4`. If we add elements after it, they'll extend outside the container. Instead, the REC elements should sit BETWEEN the URL bar and the Go button, or the Go button should move left to make room.

      Better approach: Place REC label and note button between URL bar and Go button:
      ```
      [URL bar] [● REC] [📝] [→/✕]
      ```

      Update constraints:
      - URL bar trailing → recLabel.leading - 4 (when recording)
      - recLabel trailing → noteBtn.leading - 4
      - noteBtn trailing → goBtn.leading - 4
      - goBtn trailing → container.trailing - 4

      BUT when not recording, REC and note are hidden. The URL bar should expand to fill the space. Use constraint priorities or swap the trailing constraint.

      Simplest approach: always have the constraint chain `urlBar → recLabel → noteBtn → goBtn → trailing`, but when hidden the intrinsic content size of the hidden views collapses to zero. With `isHidden = true`, Auto Layout still reserves spacing from the constant values.

      **Simplest correct approach:** Use a fixed layout where recLabel and noteBtn are always in the constraint chain, but use `NSLayoutConstraint` that can be activated/deactivated:

      ```swift
      // Two URL bar trailing constraints — swap based on recording state
      private var urlBarToGoConstraint: NSLayoutConstraint?   // direct: urlBar → goBtn
      private var urlBarToRecConstraint: NSLayoutConstraint?  // recording: urlBar → recLabel

      // In init:
      let urlToGo = urlBar.trailingAnchor.constraint(equalTo: goBtn.leadingAnchor, constant: -4)
      let urlToRec = urlBar.trailingAnchor.constraint(equalTo: recLabel.leadingAnchor, constant: -4)
      urlToRec.isActive = false  // inactive by default
      urlToGo.isActive = true    // active by default

      self.urlBarToGoConstraint = urlToGo
      self.urlBarToRecConstraint = urlToRec
      ```

      In `updateRecordingUI()`:
      ```swift
      func updateRecordingUI(recording: Bool) {
          recLabel?.isHidden = !recording
          addNoteButton?.isHidden = !recording

          if recording {
              urlBarToGoConstraint?.isActive = false
              urlBarToRecConstraint?.isActive = true
          } else {
              urlBarToRecConstraint?.isActive = false
              urlBarToGoConstraint?.isActive = true
          }
      }
      ```

   4. Implement the Add Note action:
      ```swift
      @objc private func addNoteAction(_ sender: NSButton) {
          guard let recorder = learnRecorder, recorder.state == .recording else { return }

          let alert = NSAlert()
          alert.messageText = "Add Annotation"
          alert.informativeText = "Describe what you just did or note something important for this step."
          alert.addButton(withTitle: "Add")
          alert.addButton(withTitle: "Cancel")

          let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 260, height: 80))
          scrollView.hasVerticalScroller = true
          scrollView.borderType = .bezelBorder

          let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 260, height: 80))
          textView.isEditable = true
          textView.isRichText = false
          textView.font = NSFont.systemFont(ofSize: 13)
          textView.isVerticallyResizable = true
          textView.isHorizontallyResizable = false
          textView.autoresizingMask = [.width]
          textView.textContainer?.widthTracksTextView = true

          scrollView.documentView = textView
          alert.accessoryView = scrollView

          let response = alert.runModal()
          if response == .alertFirstButtonReturn {
              let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
              if !text.isEmpty {
                  let _ = recorder.addAnnotation(text: text)
              }
          }
      }
      ```

   5. Add a public method for TabManager to toggle the recording UI:
      ```swift
      func setRecordingUI(active: Bool) {
          updateRecordingUI(recording: active)
      }
      ```

   6. Update `TabManager.startLearnMode()` and `stopLearnMode()` to toggle UI:
      In `TabManager.swift`:
      ```swift
      // In startLearnMode, after injecting JS:
      for tab in tabs.values {
          tab.startLearnMode()
          tab.setRecordingUI(active: true)
      }

      // In stopLearnMode, after removing JS:
      for tab in tabs.values {
          tab.stopLearnMode()
          tab.setRecordingUI(active: false)
      }
      ```

      Also in `createTab()`, if recording:
      ```swift
      if learnRecorder.state == .recording {
          tab.startLearnMode()
          tab.setRecordingUI(active: true)
          // ... log tab.created action
      }
      ```

   **CRITICAL:** The `addNoteAction` calls `alert.runModal()` which blocks the main thread. This is acceptable for a simple annotation dialog — it's the standard AppKit pattern for modal alerts. The user types their note and clicks Add. During this time, the browser window is blocked, which is fine since the user is annotating, not browsing.

   **DO NOT** use a sheet (`alert.beginSheetModal`) — it's more complex and the modal behavior is actually desirable here (user focuses on writing the note).

   **Verification:**
   - Build succeeds
   - Launch app, verify no REC indicator or note button visible (default state)
   - Test via socat: send `learn.start`, verify indicator appears
   - Click Add Note button, verify alert with text area appears
   - Send `learn.stop`, verify indicator and button disappear

   ---

   #### Work Item: `learn-sdk-methods`

   **Goal:** Add learn mode methods to both Python SDK clients.

   **Implementation in `sdk/python/aslan_browser/client.py` (sync):**

   Add three methods to the `AslanBrowser` class:

   ```python
   def learn_start(self, name: str) -> dict:
       """Start learn mode recording."""
       return self._call("learn.start", {"name": name})

   def learn_stop(self) -> dict:
       """Stop learn mode recording. Returns full action log."""
       return self._call("learn.stop")

   def learn_status(self) -> dict:
       """Get learn mode status."""
       return self._call("learn.status")
   ```

   **Implementation in `sdk/python/aslan_browser/async_client.py` (async):**

   Add the same three methods with `async`:

   ```python
   async def learn_start(self, name: str) -> dict:
       """Start learn mode recording."""
       return await self._call("learn.start", {"name": name})

   async def learn_stop(self) -> dict:
       """Stop learn mode recording. Returns full action log."""
       return await self._call("learn.stop")

   async def learn_status(self) -> dict:
       """Get learn mode status."""
       return await self._call("learn.status")
   ```

   **Also update `sdk/python/aslan_browser/__init__.py`** if needed — these methods are on the existing classes, so no import changes should be necessary. Verify.

   **Verification:**
   - `python3 -c "from aslan_browser import AslanBrowser; print('OK')"`
   - No import errors

   ---

   #### Work Item: `learn-cli-commands`

   **Goal:** Add `aslan learn start/stop/status` commands to the CLI.

   **Implementation in `sdk/python/aslan_browser/cli.py`:**

   1. Add a `learn` subcommand group to the argparse parser. Pattern: follow how existing commands like `tab:new`, `tab:close` work — or add `learn` as a top-level command with a required positional arg for the sub-action.

      Recommended: `aslan learn start <name>`, `aslan learn stop`, `aslan learn status` — three separate commands in the parser.

      ```python
      # In the command registration section:
      learn_start_parser = subparsers.add_parser("learn:start", help="Start learn mode recording")
      learn_start_parser.add_argument("name", help="Recording name (e.g., reddit-create-post)")

      learn_stop_parser = subparsers.add_parser("learn:stop", help="Stop learn mode recording")
      learn_stop_parser.add_argument("--json", action="store_true", help="Output full action log as JSON")

      learn_status_parser = subparsers.add_parser("learn:status", help="Check learn mode status")
      ```

      Note: using `learn:start` / `learn:stop` / `learn:status` (with colon) to match existing CLI patterns like `tab:new`, `tab:close`, `tab:use`, `tab:wait`.

   2. Implement handlers:
      ```python
      def cmd_learn_start(args, browser):
          result = browser.learn_start(args.name)
          print(f"Recording: {args.name}")
          print(f"Screenshots: {result.get('screenshotDir', '')}")

      def cmd_learn_stop(args, browser):
          result = browser.learn_stop()
          if getattr(args, 'json', False):
              import json
              print(json.dumps(result, indent=2))
          else:
              name = result.get('name', '?')
              count = result.get('actionCount', 0)
              duration = result.get('duration', 0)
              print(f"Stopped: {name}")
              print(f"Actions: {count}")
              print(f"Duration: {duration / 1000:.1f}s")
              print(f"Screenshots: {result.get('screenshotDir', '')}")

      def cmd_learn_status(args, browser):
          result = browser.learn_status()
          if result.get('recording'):
              print(f"Recording: {result.get('name', '?')} ({result.get('actionCount', 0)} actions)")
          else:
              print("Not recording")
      ```

   3. Wire handlers in the command dispatch.

   **Verification:**
   - `aslan learn:status` returns "Not recording" (with app running)
   - `aslan learn:start test-session` returns "Recording: test-session"
   - `aslan learn:status` returns "Recording: test-session (0 actions)"
   - `aslan learn:stop` returns action summary

   ---

   #### Work Item: `learn-skill-docs`

   **Goal:** Update the skill documentation so agents know about learn mode.

   **Update `skills/aslan-browser/SDK_REFERENCE.md`:**

   Add a new section:

   ```markdown
   ## Learn Mode

   ```bash
   aslan learn:start <name>     # Start recording user actions
   aslan learn:stop [--json]    # Stop recording, print summary (--json for full log)
   aslan learn:status           # Check recording state
   ```

   Learn mode records all user actions (clicks, typing, navigation, scrolling) across all tabs.
   The agent starts recording, the user demonstrates a task, then the agent stops and gets the action log.
   Use the log to generate a playbook in `knowledge/playbooks/`.
   ```

   **Update `skills/aslan-browser/SKILL.md`:**

   Add a new section after the Knowledge Compilation section:

   ```markdown
   ## 4. Learn Mode — User-Taught Playbooks

   When the user wants to teach a new task:

   1. User says "let me teach you how to [task] on [site]"
   2. Start recording:
      ```bash
      aslan learn:start <site>-<task>
      ```
   3. Tell user: "Recording. Go ahead and perform the task in the browser. Click the 📝 button to add notes. Tell me when you're done."
   4. WAIT for user to say they're done. Do NOT interact with the browser during recording.
   5. Stop recording:
      ```bash
      aslan learn:stop --json
      ```
   6. Read the action log. Generate a playbook following the format in `knowledge/playbooks/`.
   7. Save to `knowledge/playbooks/<site>-<task>.md`
   8. Tell user: "Playbook saved. I'll follow it next time."

   **Playbook format** — match existing playbooks. Include:
   - Inputs (what varies per execution)
   - Prerequisites (URL, login state)
   - Steps (numbered, with selectors and commands)
   - Known notes (from user annotations)
   ```

   **Update `skills/aslan-browser/knowledge/core.md`:**

   Add to the end:

   ```markdown
   ## Learn Mode

   - `aslan learn:start <name>` begins recording all user actions across all tabs.
   - `aslan learn:stop --json` returns the full action log with composedPath data for shadow DOM.
   - Screenshots are saved to `/tmp/aslan-learn/<name>/` — review them for visual context.
   - The action log includes `composedPath` arrays that trace through shadow DOM boundaries — use these to write the correct JS eval selectors in the playbook.
   - Input events are debounced (300ms) — the log captures the final value, not every keystroke.
   - Navigation events are logged automatically — the page URL/title at each step is always available.
   - Do NOT browse during recording. The user is performing the task.
   ```

   **Verification:**
   - All three files updated
   - No broken markdown formatting
   - Learn mode commands are documented

   ---

   #### Work Item: `learn-integration-test`

   **Goal:** End-to-end test that starts recording, performs some actions via the SDK (simulating what would happen if a user clicked), stops, and verifies the action log.

   **Create `sdk/python/tests/test_learn.py`:**

   ```python
   """Integration tests for learn mode."""
   import json
   import os
   import pytest
   from aslan_browser import AslanBrowser

   @pytest.fixture
   def browser():
       with AslanBrowser() as b:
           yield b

   def test_learn_status_default(browser):
       """Learn mode is off by default."""
       status = browser.learn_status()
       assert status["recording"] is False
       assert status["actionCount"] == 0

   def test_learn_start_stop(browser):
       """Start and stop recording."""
       result = browser.learn_start("test-session")
       assert result["ok"] is True
       assert result["name"] == "test-session"
       assert "screenshotDir" in result

       status = browser.learn_status()
       assert status["recording"] is True
       assert status["name"] == "test-session"

       log = browser.learn_stop()
       assert log["name"] == "test-session"
       assert "duration" in log
       assert "actions" in log
       assert isinstance(log["actions"], list)

   def test_learn_start_creates_directory(browser):
       """learn.start creates the screenshot directory."""
       result = browser.learn_start("dir-test")
       screenshot_dir = result["screenshotDir"]
       assert os.path.isdir(screenshot_dir)
       browser.learn_stop()

   def test_learn_start_cleans_old_directory(browser):
       """learn.start deletes old directory if it exists."""
       browser.learn_start("cleanup-test")
       browser.learn_stop()
       # Start again with same name — should work without error
       result = browser.learn_start("cleanup-test")
       assert result["ok"] is True
       browser.learn_stop()

   def test_learn_double_start_fails(browser):
       """Cannot start recording while already recording."""
       browser.learn_start("double-test")
       with pytest.raises(Exception):  # AslanBrowserError
           browser.learn_start("another-test")
       browser.learn_stop()

   def test_learn_stop_when_not_recording_fails(browser):
       """Cannot stop when not recording."""
       with pytest.raises(Exception):  # AslanBrowserError
           browser.learn_stop()

   def test_learn_captures_navigation(browser):
       """Navigation during recording creates action entries."""
       browser.learn_start("nav-test")
       browser.navigate("https://example.com", wait_until="idle")
       # Give time for screenshot capture
       import time; time.sleep(1)
       log = browser.learn_stop()
       # Should have at least one navigation action
       nav_actions = [a for a in log["actions"] if a.get("type") == "navigation"]
       assert len(nav_actions) >= 1
       assert "example.com" in nav_actions[0].get("url", "")

   def test_learn_screenshot_files_exist(browser):
       """Screenshots are saved to disk during recording."""
       browser.learn_start("screenshot-test")
       browser.navigate("https://example.com", wait_until="idle")
       import time; time.sleep(1.5)  # Wait for screenshot capture (500ms delay + write)
       log = browser.learn_stop()
       for action in log["actions"]:
           if "screenshot" in action:
               assert os.path.exists(action["screenshot"]), f"Missing screenshot: {action['screenshot']}"
   ```

   **CRITICAL:** Tests must clean up after themselves — always call `learn_stop()` if `learn_start()` was called, even in failure paths. Use try/finally or pytest fixtures.

   **CRITICAL:** Screenshot capture is asynchronous (500ms delay + file write). Tests must sleep long enough for screenshots to be written before checking.

   **DO NOT** test user-initiated click/type actions — those require actual UI interaction which can't be simulated in pytest. Test what the SDK can trigger: navigation events, start/stop lifecycle, directory management.

   **Verification:**
   - All tests pass: `cd sdk/python && python3 -m pytest tests/test_learn.py -v`

   ---

6. **Verify build:**
   ```bash
   xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   ```
   - If BUILD FAILED: Read the error messages. Fix the issues. Re-verify.
   - If BUILD SUCCEEDED: Continue.

7. **Update state:**
   ```bash
   jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-10-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-10-plan.json
   ```

8. **Update notes:**
   Add any discoveries, edge cases, or gotchas to `docs/workflows/notes.md`.

9. **Return to step 1.**

### 3. Completion

1. Show final progress:
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-10-plan.json
   ```

2. Verify the complete phase:
   - All work items have status `"done"`.
   - App builds cleanly.
   - `aslan learn:status` returns "Not recording" (manual test via CLI).
   - `aslan learn:start test` → ● REC indicator appears in browser window (manual test).
   - Add Note button visible, clicking opens text area dialog (manual test).
   - Click around in the browser, then `aslan learn:stop --json` → action log with composedPath data (manual test).
   - Screenshots exist in `/tmp/aslan-learn/test/` (manual test).
   - `aslan learn:stop` when not recording → error (manual test).
   - No regressions: existing navigation, tree, click, fill, tabs all still work.
   - Python integration tests pass.

3. Rebuild Release binary:
   ```bash
   xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Release build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   ```

4. Add to `notes.md`:
   ```
   ## Phase 10 — Learn Mode

   **Status:** Complete ✅

   ### Changes
   - LearnRecorder: global recording state machine with action storage and screenshot capture
   - Learn-mode JS event listeners injected on-demand: click, input, keydown, scroll with composedPath()
   - Recording UI: ● REC indicator + Add Note button (SF Symbol) in toolbar
   - Navigation and tab lifecycle events captured during recording
   - JSON-RPC: learn.start, learn.stop, learn.status, learn.note
   - Python SDK: learn_start(), learn_stop(), learn_status()
   - CLI: aslan learn:start/stop/status
   - Skill docs updated with learn mode workflow
   ```

5. **Commit all changes** (see conventions.md §8):
   ```bash
   git add -A
   git status  # verify no junk files
   git commit -m "Phase 10: Learn mode — record user actions for playbook generation

   - Add LearnRecorder with recording state machine and screenshot capture
   - Add learn-mode JS listeners (click, input, keydown, scroll) with composedPath()
   - Add recording UI (REC indicator + Add Note button with system symbol)
   - Capture navigation and tab lifecycle events during recording
   - Wire learn.start, learn.stop, learn.status, learn.note JSON-RPC methods
   - Add Python SDK methods and CLI commands (aslan learn:start/stop/status)
   - Update skill docs with learn mode workflow
   - Add integration tests for learn mode lifecycle"
   ```

6. Update `docs/workflows/README.md` to include Phase 10 in the phase table.
