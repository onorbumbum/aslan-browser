# Phase 1 — Skeleton

Convert the SwiftUI template to AppKit, create BrowserTab with WKWebView, implement navigate/evaluate/screenshot. At the end of this phase, the app launches, loads a URL in a visible browser window, evaluates JS, and saves a screenshot to disk.

**State file:** `docs/workflows/state/phase-1-plan.json`
**Dependencies:** None (first phase)

---

## Tools

### State Queries

```bash
# Get next pending work item ID
jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-1-plan.json | head -1

# Get full details of a specific work item
jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-1-plan.json

# Get progress summary
jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-1-plan.json

# Get metadata
jq '.metadata' docs/workflows/state/phase-1-plan.json
```

### State Mutations

```bash
# Mark item as done
jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-1-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-1-plan.json

# Mark item as error
jq --arg id "ITEM_ID" --arg err "Error description" '(.workItems[] | select(.id == $id)) |= . + {"status": "error", "errorMsg": $err}' docs/workflows/state/phase-1-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-1-plan.json
```

### Build & Verify

```bash
# Compile the project (primary verification gate)
xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | tail -20

# Quick compile check (faster, just errors)
xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

# Run the app (for smoke test)
open -a "$(find ~/Library/Developer/Xcode/DerivedData -name 'aslan-browser.app' -path '*/Debug/*' | head -1)"
```

---

## Workflow

### 1. Setup (One-time)

1. Read configuration:
   ```bash
   jq '.metadata' docs/workflows/state/phase-1-plan.json
   ```
   Store these values for later use:
   - `projectRoot`
   - `sourceDir`
   - `scheme`

2. Read these files in full (parallel reads):
   - `docs/workflows/conventions.md`
   - `docs/workflows/notes.md`
   - `docs/prd.md` (reference only — conventions.md has final decisions)

3. Check progress:
   ```bash
   jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-1-plan.json
   ```
   If all items are done, go to Completion.

4. Read existing source files to understand current state:
   ```bash
   ls -la aslan-browser/
   ```
   Read any `.swift` files that already exist in `aslan-browser/` to understand what's been built so far.

### 2. Process Work Items (Repeat for each)

1. **Find next pending item:**
   ```bash
   jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-1-plan.json | head -1
   ```
   If no pending items remain, go to Completion.

2. **Load work item details:**
   ```bash
   jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-1-plan.json
   ```

3. **Check dependencies:**
   Read the `dependsOn` array. For each dependency, verify its status is `"done"`:
   ```bash
   jq --arg id "DEP_ID" '.workItems[] | select(.id == $id) | .status' docs/workflows/state/phase-1-plan.json
   ```
   If any dependency is not done, skip this item and find the next pending item without unmet dependencies.

4. **Load context:**
   Read ALL files listed in `filesToModify` in full so they are completely in context.
   For `filesToCreate`, check if the file already exists (from a partial previous attempt).

5. **Implement:**
   Follow the work item's `description` exactly. Apply conventions from `conventions.md`.

   **Decision framework for implementation choices:**
   - Is there a pattern in `conventions.md` for this? → Follow it exactly.
   - Is there a code example in `conventions.md`? → Use it as the starting template.
   - Is there ambiguity in the work item description? → Choose the simplest approach. Add a note to `notes.md` explaining the decision.
   - Does this require importing a new framework? → Only import what's needed. AppKit and WebKit are expected. Do NOT add SwiftUI or SwiftData.

   **CRITICAL constraints for this phase:**
   - Do NOT import SwiftUI anywhere. This is a pure AppKit app.
   - Do NOT import SwiftData anywhere. There is no data model.
   - Do NOT create any UI beyond the WKWebView in its NSWindow.
   - Do NOT add networking/socket code. That is Phase 2.

6. **Verify build:**
   ```bash
   xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   ```
   - If BUILD FAILED: Read the error messages. Fix the issues. Re-verify. Do NOT proceed until build succeeds.
   - If BUILD SUCCEEDED: Continue.

7. **Work-item-specific verification:**

   For `setup-appkit`:
   - Verify `aslan_browserApp.swift`, `ContentView.swift`, `Item.swift` are deleted.
   - Verify `AppDelegate.swift` exists with `@main` and `NSApplicationDelegate`.
   - Verify no SwiftUI or SwiftData imports remain anywhere:
     ```bash
     grep -r "SwiftUI\|SwiftData" aslan-browser/*.swift
     ```
     This should return nothing.

   For `browser-tab`:
   - Verify `BrowserTab.swift` exists with `@MainActor class BrowserTab`.
   - Verify it creates an NSWindow and WKWebView.

   For `navigate`:
   - Verify `BrowserTab` has an async `navigate` method.
   - Verify WKNavigationDelegate is implemented.

   For `evaluate`:
   - Verify `BrowserTab` has an async `evaluate` method using `callAsyncJavaScript`.

   For `screenshot`:
   - Verify `BrowserTab` has an async `screenshot` method returning base64 string.

   For `hidden-flag`:
   - Verify `CommandLine.arguments` is checked for `--hidden`.

   For `smoke-test`:
   - Build AND run the app:
     ```bash
     xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
     ```
   - After running, verify screenshot was saved:
     ```bash
     ls -la /tmp/aslan-screenshot.jpg
     ```
   - Check console output for title and URL.

8. **Update state:**
   ```bash
   jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-1-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-1-plan.json
   ```

9. **Update notes:**
   If anything unexpected was discovered — edge cases, API quirks, decisions made — append to `docs/workflows/notes.md`.

10. **Return to step 1.**

### 3. Completion

1. Show final progress:
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-1-plan.json
   ```

2. Verify the complete phase:
   - All 7 work items have status `"done"`.
   - App builds cleanly.
   - No SwiftUI/SwiftData imports remain.
   - App launches, shows a browser window with example.com, and saves a screenshot.

3. Summarize:
   - What was built
   - Any notes or discoveries added
   - Any issues to watch for in Phase 2

4. Add to `notes.md`: "Phase 1 complete. App launches with AppKit lifecycle, BrowserTab loads pages, navigate/evaluate/screenshot working."
