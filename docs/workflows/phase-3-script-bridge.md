# Phase 3 — ScriptBridge + Readiness Detection

Inject a JavaScript automation bridge into every page for DOM stability detection, network idle tracking, and element waiting. At the end of this phase, `navigate(url, waitUntil: "idle")` deterministically waits for a page to be truly ready.

**State file:** `docs/workflows/state/phase-3-plan.json`
**Dependencies:** Phase 2 complete

---

## Tools

### State Queries

```bash
# Get next pending work item ID
jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-3-plan.json | head -1

# Get full details of a specific work item
jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-3-plan.json

# Get progress summary
jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-3-plan.json
```

### State Mutations

```bash
# Mark item as done
jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-3-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-3-plan.json

# Mark item as error
jq --arg id "ITEM_ID" --arg err "Error description" '(.workItems[] | select(.id == $id)) |= . + {"status": "error", "errorMsg": $err}' docs/workflows/state/phase-3-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-3-plan.json
```

### Build & Verify

```bash
# Compile
xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

# Test readiness via socket (app must be running)
echo '{"jsonrpc":"2.0","id":1,"method":"navigate","params":{"tabId":"tab0","url":"https://example.com","waitUntil":"idle"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock

# Test waitForSelector
echo '{"jsonrpc":"2.0","id":2,"method":"waitForSelector","params":{"tabId":"tab0","selector":"h1","timeout":5000}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
```

---

## Workflow

### 1. Setup (One-time)

1. Read configuration:
   ```bash
   jq '.metadata' docs/workflows/state/phase-3-plan.json
   ```

2. Read in full (parallel reads):
   - `docs/workflows/conventions.md`
   - `docs/workflows/notes.md`

3. Check progress:
   ```bash
   jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-3-plan.json
   ```

4. **Verify Phase 2 is complete:**
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-2-plan.json
   ```

5. Read all existing source files:
   ```bash
   find aslan-browser -name "*.swift" -not -path "*/.*"
   ```
   Read each file in full. You MUST have complete context of all existing code before making changes.

### 2. Process Work Items (Repeat for each)

1. **Find next pending item:**
   ```bash
   jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-3-plan.json | head -1
   ```
   If no pending items remain, go to Completion.

2. **Load work item details:**
   ```bash
   jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-3-plan.json
   ```

3. **Check dependencies** (same pattern as Phase 1/2).

4. **Load context:**
   Read ALL files in `filesToModify` in full.
   CRITICAL: For `ScriptBridge.swift`, always read the ENTIRE file before modifying — the JS source string grows across multiple work items and you must not lose previous additions.

5. **Implement:**

   **CRITICAL constraints for this phase:**
   - All JS code is embedded as Swift string literals in `ScriptBridge.swift`. Do NOT create separate `.js` files.
   - Use multiline string literals (`"""..."""`) for readability.
   - The JS bridge lives under `window.__agent` namespace. Do NOT pollute the global scope.
   - Monkey-patching fetch/XHR must PRESERVE original behavior. Only observe, never modify requests or responses.
   - MutationObserver must watch `{ childList: true, subtree: true, attributes: true }` on document.body.
   - The DOM quiet timeout (500ms default) must be configurable — accept it as a parameter in the readiness detection.
   - Use `.page` content world for all JS evaluation (per conventions.md).
   - Messages from JS to Swift use `window.webkit.messageHandlers.agent.postMessage({type: "...", ...})`.

   **Decision framework for JS bridge design:**
   - Should this logic run in JS or Swift? → JS for anything DOM-related. Swift for coordination and state tracking.
   - Should this be a single monolithic JS string or composed from parts? → Start monolithic in one `injectedJS` property. Refactor only if it becomes unmanageable. KISS.
   - How to handle errors in injected JS? → Try-catch in JS, postMessage errors to Swift. Never let JS errors break the bridge.

   **Readiness detection architecture:**
   ```
   Page loads → WKNavigationDelegate.didFinish fires (Swift)
                MutationObserver starts watching (JS)
                fetch/XHR tracker active (JS)
                
   Readiness signals tracked in BrowserTab (Swift):
     - didFinishNavigation: Bool (from delegate)
     - domStable: Bool (from JS message after 500ms quiet)
     - networkIdle: Bool (from JS message when pending=0)
     - readyStateComplete: Bool (from evaluating document.readyState)
   
   waitForIdle() polls/awaits all 4 signals with timeout
   All signals reset on new navigation start
   ```

6. **Verify build:**
   ```bash
   xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   ```

7. **Work-item-specific verification:**

   For `script-bridge-setup`:
   - Verify ScriptBridge.swift exists with `injectedJS` static property.
   - Verify BrowserTab's WKWebViewConfiguration adds the user script.
   - Verify `window.__agent` namespace is created.

   For `message-handler`:
   - Verify WKScriptMessageHandler is registered on channel "agent".
   - Verify incoming messages are parsed by `type` field.

   For `network-tracking`:
   - Verify fetch and XMLHttpRequest are monkey-patched.
   - Verify pending count tracking logic.
   - Verify original behavior is preserved (calls pass through).

   For `dom-stability`:
   - Verify MutationObserver is created on document.body.
   - Verify debounce timer logic.

   For `readiness-detection`:
   - Verify BrowserTab has readiness state tracking.
   - Verify signals reset on navigation start.
   - Verify waitForIdle() with timeout.

   For `navigate-wait-until`:
   - Verify navigate accepts waitUntil parameter.
   - Verify MethodRouter passes waitUntil from JSON-RPC params.
   - Test via socket:
     ```bash
     echo '{"jsonrpc":"2.0","id":1,"method":"navigate","params":{"tabId":"tab0","url":"https://example.com","waitUntil":"idle"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
     ```

   For `wait-for-selector`:
   - Verify JS implementation uses MutationObserver.
   - Verify timeout handling (rejects on timeout).
   - Verify JSON-RPC method is wired.

8. **Update state:**
   ```bash
   jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-3-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-3-plan.json
   ```

9. **Update notes:**
   This phase will likely surface JS injection edge cases. Document them. Common issues:
   - Script injection timing relative to page scripts
   - Monkey-patch conflicts with page's own fetch wrappers
   - MutationObserver performance on heavy pages

10. **Return to step 1.**

### 3. Completion

1. Show final progress:
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-3-plan.json
   ```

2. Verify the complete phase:
   - All 7 work items have status `"done"`.
   - App builds cleanly.
   - `navigate(url, waitUntil: "idle")` works — waits for page to be truly ready.
   - `waitForSelector` works — finds elements or times out.
   - JS bridge doesn't break page functionality.

3. Summarize and add to `notes.md`.
