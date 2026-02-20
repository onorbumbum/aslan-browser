# Phase 2 — Socket Server

Add SwiftNIO Unix socket server with JSON-RPC 2.0 protocol. At the end of this phase, the app listens on `/tmp/aslan-browser.sock` and responds to navigate/evaluate/screenshot commands from any client that speaks NDJSON JSON-RPC.

**State file:** `docs/workflows/state/phase-2-plan.json`
**Dependencies:** Phase 1 complete

---

## Tools

### State Queries

```bash
# Get next pending work item ID
jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-2-plan.json | head -1

# Get full details of a specific work item
jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-2-plan.json

# Get progress summary
jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-2-plan.json

# Get metadata
jq '.metadata' docs/workflows/state/phase-2-plan.json
```

### State Mutations

```bash
# Mark item as done
jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-2-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-2-plan.json

# Mark item as error
jq --arg id "ITEM_ID" --arg err "Error description" '(.workItems[] | select(.id == $id)) |= . + {"status": "error", "errorMsg": $err}' docs/workflows/state/phase-2-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-2-plan.json
```

### Build & Verify

```bash
# Compile the project
xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

# Test socket connection (after app is running)
echo '{"jsonrpc":"2.0","id":1,"method":"getTitle","params":{"tabId":"tab0"}}' | socat - UNIX-CONNECT:/tmp/aslan-browser.sock

# Check if socket exists
ls -la /tmp/aslan-browser.sock
```

### Integration Test

```bash
# Run the Python integration test (app must be running first)
python3 tests/test_socket.py
```

---

## Workflow

### 1. Setup (One-time)

1. Read configuration:
   ```bash
   jq '.metadata' docs/workflows/state/phase-2-plan.json
   ```
   Store: `projectRoot`, `sourceDir`, `socketPath`, `scheme`.

2. Read these files in full (parallel reads):
   - `docs/workflows/conventions.md`
   - `docs/workflows/notes.md`

3. Check progress:
   ```bash
   jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-2-plan.json
   ```

4. Read all existing source files to understand current state:
   ```bash
   find aslan-browser -name "*.swift" -not -path "*/.*"
   ```
   Read each file in full.

5. **Verify Phase 1 is complete:**
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-1-plan.json
   ```
   All items must be `"done"`. If not, abort and tell the user to complete Phase 1 first.

### 2. Process Work Items (Repeat for each)

1. **Find next pending item:**
   ```bash
   jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-2-plan.json | head -1
   ```
   If no pending items remain, go to Completion.

2. **Load work item details:**
   ```bash
   jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-2-plan.json
   ```

3. **Check dependencies:**
   For each ID in `dependsOn`, verify status is `"done"`:
   ```bash
   jq --arg id "DEP_ID" '.workItems[] | select(.id == $id) | .status' docs/workflows/state/phase-2-plan.json
   ```
   If any dependency is not done, skip and find next eligible item.

4. **Handle manual steps:**
   If the work item has `"manual": true` (the `add-swiftnio` item):
   - STOP and instruct the user:
     ```
     MANUAL STEP REQUIRED:
     1. Open aslan-browser.xcodeproj in Xcode
     2. File → Add Package Dependencies
     3. Enter: https://github.com/apple/swift-nio.git
     4. Version: Up to Next Major (2.0.0)
     5. Add these libraries to the aslan-browser target:
        - NIO
        - NIOCore
        - NIOPosix
        - NIOFoundationCompat
     6. Confirm the build still succeeds
     ```
   - After user confirms, verify:
     ```bash
     xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
     ```
   - If build succeeds, mark as done and continue.

5. **Load context:**
   Read ALL files listed in `filesToModify` in full.
   For `filesToCreate`, check if target directory exists:
   ```bash
   ls -la aslan-browser/Models/ 2>/dev/null
   ```
   Create `Models/` directory if needed:
   ```bash
   mkdir -p aslan-browser/Models
   ```

6. **Implement:**
   Follow the work item's `description` exactly. Apply conventions from `conventions.md`.

   **CRITICAL constraints for this phase:**
   - The JSON-RPC protocol MUST be NDJSON (newline-delimited). Each message is one line terminated by `\n`. See conventions.md for protocol details.
   - Use `LineBasedFrameDecoder` from SwiftNIO for framing. Do NOT implement custom framing.
   - Screenshots return base64 in JSON-RPC response. Do NOT create a separate binary endpoint.
   - All WKWebView calls MUST dispatch to `@MainActor`. NIO handlers run on the event loop, not the main thread.
   - Error responses MUST use the JSON-RPC error codes defined in conventions.md.
   - Do NOT add tab management yet. Use the single default BrowserTab. TabManager comes in Phase 5.

   **Decision framework for NIO architecture:**
   - Channel pipeline: `LineBasedFrameDecoder` → `JSONRPCHandler` (custom handler)
   - `JSONRPCHandler` parses JSON, calls `MethodRouter`, writes response
   - `MethodRouter` holds reference to `BrowserTab`, dispatches method calls
   - Main thread dispatch: `Task { @MainActor in let result = try await tab.navigate(...) }`
   - Write response back on the NIO event loop: use `context.eventLoop.execute { ... }`

7. **Verify build:**
   ```bash
   xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   ```
   If BUILD FAILED: fix and re-verify. Do NOT proceed until build succeeds.

8. **Work-item-specific verification:**

   For `rpc-models`:
   - Verify RPCMessage.swift exists in Models/.
   - Verify structs handle flexible JSON types for params/result.

   For `socket-server`:
   - Verify SocketServer.swift creates Unix socket listener.
   - Verify it removes stale socket file on startup.

   For `json-rpc-handler`:
   - Verify it parses JSON-RPC requests and writes responses.
   - Verify error handling for malformed JSON.

   For `method-router`:
   - Verify all Phase 1 methods are routed: navigate, evaluate, screenshot, getTitle, getURL.

   For `wire-server`:
   - Verify AppDelegate starts SocketServer after BrowserTab is ready.
   - Verify socket path is printed to stdout.
   - Verify hardcoded smoke test from Phase 1 is removed.

   For `error-handling`:
   - Verify BrowserError enum exists with all error cases.
   - Verify JSON-RPC error code mapping.

   For `integration-test`:
   - Verify test script exists and covers: valid navigate, valid evaluate, valid screenshot, invalid method error, malformed JSON error.
   - Run the app, then run the test:
     ```bash
     python3 tests/test_socket.py
     ```

9. **Update state:**
   ```bash
   jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-2-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-2-plan.json
   ```

10. **Update notes:**
    Record any discoveries about SwiftNIO patterns, JSON-RPC edge cases, or threading issues.

11. **Return to step 1.**

### 3. Completion

1. Show final progress:
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-2-plan.json
   ```

2. Verify the complete phase:
   - All 8 work items have status `"done"`.
   - App builds cleanly.
   - App starts and listens on `/tmp/aslan-browser.sock`.
   - Integration test passes.
   - Socket removed on app termination (or stale socket handled on restart).

3. Summarize what was built and any notes added.

4. Add to `notes.md`: "Phase 2 complete. Socket server running on /tmp/aslan-browser.sock. JSON-RPC methods: navigate, evaluate, screenshot, getTitle, getURL."

5. **Commit all changes** (see conventions.md §8):
   ```bash
   git add -A
   git status  # verify no junk files
   git commit -m "Phase 2: Socket server with JSON-RPC 2.0 over Unix socket"
   ```
