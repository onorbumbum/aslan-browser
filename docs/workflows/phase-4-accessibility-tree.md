# Phase 4 — Accessibility Tree

Build the accessibility tree extractor — the highest-value feature. A DOM walker that produces a flat, token-efficient representation of interactive page elements that AI agents can reason about. At the end of this phase, agents can get an a11y tree, pick elements by ref, and interact via click/fill/select.

**State file:** `docs/workflows/state/phase-4-plan.json`
**Dependencies:** Phase 3 complete

---

## Tools

### State Queries

```bash
# Get next pending work item ID
jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-4-plan.json | head -1

# Get full details of a specific work item
jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-4-plan.json

# Get progress summary
jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-4-plan.json
```

### State Mutations

```bash
# Mark item as done
jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-4-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-4-plan.json

# Mark item as error
jq --arg id "ITEM_ID" --arg err "Error description" '(.workItems[] | select(.id == $id)) |= . + {"status": "error", "errorMsg": $err}' docs/workflows/state/phase-4-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-4-plan.json
```

### Build & Verify

```bash
# Compile
xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

# Test a11y tree extraction (app must be running, navigated to a page)
echo '{"jsonrpc":"2.0","id":1,"method":"navigate","params":{"tabId":"tab0","url":"https://github.com/login","waitUntil":"idle"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
echo '{"jsonrpc":"2.0","id":2,"method":"getAccessibilityTree","params":{"tabId":"tab0"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock

# Test ref-based interaction
echo '{"jsonrpc":"2.0","id":3,"method":"click","params":{"tabId":"tab0","selector":"@e0"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
```

---

## Workflow

### 1. Setup (One-time)

1. Read configuration:
   ```bash
   jq '.metadata' docs/workflows/state/phase-4-plan.json
   ```

2. Read in full (parallel reads):
   - `docs/workflows/conventions.md`
   - `docs/workflows/notes.md`

3. Check progress:
   ```bash
   jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-4-plan.json
   ```

4. **Verify Phase 3 is complete:**
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-3-plan.json
   ```

5. Read all existing source files in full:
   ```bash
   find aslan-browser -name "*.swift" -not -path "*/.*"
   ```
   Read EVERY file. The a11y tree JS will be added to ScriptBridge.swift which already has readiness detection code from Phase 3.

### 2. Process Work Items (Repeat for each)

1. **Find next pending item:**
   ```bash
   jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-4-plan.json | head -1
   ```
   If no pending items remain, go to Completion.

2. **Load work item details:**
   ```bash
   jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-4-plan.json
   ```

3. **Check dependencies.**

4. **Load context:**
   Read ALL files in `filesToModify` in full.
   CRITICAL: Read `ScriptBridge.swift` completely — it contains the JS from Phase 3 that MUST be preserved.
   Read `docs/prd.md` Section 5 (Accessibility Tree Extraction) for the complete specification.

5. **Implement:**

   **CRITICAL constraints for this phase:**
   - The a11y tree is the MOST IMPORTANT feature. Get it right.
   - Each element gets a ref like `@e0`, `@e1`, etc. Refs are sequential, starting from 0.
   - Set `data-agent-ref` attribute on each element so CSS selector `[data-agent-ref="@e0"]` works.
   - Refs are ephemeral — they reset on each `extractA11yTree()` call. Document this.
   - The tree is a FLAT array, not nested. No parent-child relationships.
   - Do NOT include hidden elements. Check: `display:none`, `visibility:hidden`, `aria-hidden="true"`, zero-size bounding rect.
   - `name` resolution is critical — follow the exact priority chain in the PRD.
   - Truncate visible textContent to 80 chars. Collapse whitespace.
   - Include `value` for inputs, selects, textareas. Omit for other elements.

   **Role inference map:**
   ```
   A → link
   BUTTON → button
   INPUT[type=text|email|password|search|tel|url|number] → textbox
   INPUT[type=checkbox] → checkbox
   INPUT[type=radio] → radio
   INPUT[type=submit|button|reset] → button
   SELECT → combobox
   TEXTAREA → textbox
   IMG → img
   H1-H6 → heading
   NAV → navigation
   MAIN → main
   HEADER → banner
   FOOTER → contentinfo
   ASIDE → complementary
   FORM → form
   TABLE → table
   UL/OL → list
   LI → listitem
   Explicit role attribute → use as-is
   ```

   **Name resolution chain (in order):**
   1. `aria-label` attribute
   2. `aria-labelledby` → get textContent of referenced element by ID
   3. Associated `<label>` (via `for` attribute matching input `id`, or parent `<label>`)
   4. `placeholder` attribute
   5. `title` attribute
   6. Visible `textContent` (trimmed, whitespace-collapsed, truncated to 80 chars)

   **Decision framework for interaction methods:**
   - Target resolution: if `selector` starts with `@`, resolve via `[data-agent-ref="${selector}"]`. Otherwise, use as CSS selector directly.
   - `click`: `element.focus()` then `element.click()`. This covers standard click behavior.
   - `fill`: Set `element.value`, then dispatch `new Event('input', {bubbles: true})` and `new Event('change', {bubbles: true})`. This triggers form validation and frameworks that listen for these events.
   - `select`: Set `element.value` on the `<select>`, then dispatch `change` event.
   - `keypress`: `element.dispatchEvent(new KeyboardEvent('keydown', {...}))` then `keyup`.
   - `scroll`: `window.scrollTo(x, y)` for page scroll, or `element.scrollIntoView()` if targeting an element.

6. **Verify build:**
   ```bash
   xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   ```

7. **Work-item-specific verification:**

   For `a11y-model`:
   - Verify A11yNode.swift exists in Models/ with all fields.

   For `dom-walker`:
   - Verify `__agent.extractA11yTree()` function exists in ScriptBridge JS.
   - Verify role inference covers the map above.
   - Verify hidden elements are excluded.

   For `name-resolution`:
   - Verify all 6 steps of the name resolution chain.

   For `ref-assignment`:
   - Verify refs are sequential (@e0, @e1, ...).
   - Verify `data-agent-ref` is set on DOM elements.

   For `a11y-method`:
   - Verify JSON-RPC method works end-to-end:
     ```bash
     echo '{"jsonrpc":"2.0","id":1,"method":"navigate","params":{"tabId":"tab0","url":"https://example.com","waitUntil":"idle"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
     echo '{"jsonrpc":"2.0","id":2,"method":"getAccessibilityTree","params":{"tabId":"tab0"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
     ```
   - Verify the response contains a `tree` array with properly structured nodes.

   For `ref-interaction`:
   - Verify click, fill, select, keypress, scroll methods exist.
   - Verify target resolution handles both `@eN` refs and CSS selectors.
   - Test click by ref:
     ```bash
     echo '{"jsonrpc":"2.0","id":3,"method":"click","params":{"tabId":"tab0","selector":"@e0"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
     ```

8. **Update state:**
   ```bash
   jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-4-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-4-plan.json
   ```

9. **Update notes:**
   This phase will surface many edge cases in DOM walking — missing roles, name resolution failures on specific sites, hidden element detection gaps. Document ALL of them.

10. **Return to step 1.**

### 3. Completion

1. Show final progress:
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-4-plan.json
   ```

2. Verify the complete phase:
   - All 6 work items have status `"done"`.
   - App builds cleanly.
   - `getAccessibilityTree` returns structured nodes for real pages.
   - Click/fill/select work with both `@eN` refs and CSS selectors.
   - The full agent workflow works: navigate → getAccessibilityTree → fill by ref → click by ref.

3. Test the core agent workflow end-to-end:
   ```bash
   # Navigate
   echo '{"jsonrpc":"2.0","id":1,"method":"navigate","params":{"tabId":"tab0","url":"https://example.com","waitUntil":"idle"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
   # Get tree
   echo '{"jsonrpc":"2.0","id":2,"method":"getAccessibilityTree","params":{"tabId":"tab0"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock
   # The tree output is what an LLM would consume to decide actions
   ```

4. Summarize and add to `notes.md`.
