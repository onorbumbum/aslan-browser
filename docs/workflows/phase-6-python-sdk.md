# Phase 6 — Python SDK + Polish

Build a thin Python client library for aslan-browser, write documentation, and run performance benchmarks. At the end of this phase, `pip install` works and agents can use aslan-browser from Python with a clean API.

**State file:** `docs/workflows/state/phase-6-plan.json`
**Dependencies:** Phase 5 complete

---

## Tools

### State Queries

```bash
# Get next pending work item ID
jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-6-plan.json | head -1

# Get full details of a specific work item
jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-6-plan.json

# Get progress summary
jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-6-plan.json
```

### State Mutations

```bash
# Mark item as done
jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-6-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-6-plan.json

# Mark item as error
jq --arg id "ITEM_ID" --arg err "Error description" '(.workItems[] | select(.id == $id)) |= . + {"status": "error", "errorMsg": $err}' docs/workflows/state/phase-6-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-6-plan.json
```

### Build & Verify

```bash
# Verify Python package structure
cd sdk/python && python3 -c "from aslan_browser import AslanBrowser; print('Import OK')"

# Run SDK integration tests (app must be running)
cd sdk/python && python3 -m pytest tests/ -v

# Install in editable mode for testing
cd sdk/python && pip install -e .
```

---

## Workflow

### 1. Setup (One-time)

1. Read configuration:
   ```bash
   jq '.metadata' docs/workflows/state/phase-6-plan.json
   ```
   Store: `projectRoot`, `sdkDir`, `socketPath`.

2. Read in full (parallel reads):
   - `docs/workflows/conventions.md`
   - `docs/workflows/notes.md`

3. Check progress:
   ```bash
   jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-6-plan.json
   ```

4. **Verify Phase 5 is complete:**
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-5-plan.json
   ```

5. Read MethodRouter.swift to understand the complete JSON-RPC API surface:
   ```bash
   find aslan-browser -name "MethodRouter.swift"
   ```
   Read it in full. This defines every method the Python SDK must support.

6. Read the integration test from Phase 2/5 for API usage reference:
   ```bash
   cat tests/test_socket.py
   ```

### 2. Process Work Items (Repeat for each)

1. **Find next pending item:**
   ```bash
   jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-6-plan.json | head -1
   ```
   If no pending items remain, go to Completion.

2. **Load work item details:**
   ```bash
   jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-6-plan.json
   ```

3. **Check dependencies.**

4. **Load context:**
   Read all files in `filesToModify` in full.
   For the Python SDK, also re-read `conventions.md` protocol section for JSON-RPC format.

5. **Implement:**

   **CRITICAL constraints for this phase:**
   - The Python SDK has ZERO external dependencies. Only stdlib (socket, json, asyncio, base64, struct).
   - The SDK must work with Python 3.10+.
   - Method names in Python use snake_case (e.g., `get_accessibility_tree`, `wait_for_selector`).
   - All methods that take `tab_id` should default to `"tab0"` so single-tab usage doesn't require passing it.
   - Screenshots return `bytes` (decoded from base64), not base64 strings. The SDK does the conversion.
   - JSON-RPC errors become Python exceptions. Create `AslanBrowserError(code, message)`.
   - The sync client is the primary client. The async client mirrors its API with `async`/`await`.
   - Do NOT use `requests`, `httpx`, `aiohttp`, or any HTTP library. This is raw Unix socket.

   **Sync client architecture:**
   ```python
   class AslanBrowser:
       def __init__(self, socket_path="/tmp/aslan-browser.sock"):
           self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
           self._sock.connect(socket_path)
           self._file = self._sock.makefile('rw')
           self._next_id = 0
       
       def _call(self, method: str, params: dict = None) -> Any:
           self._next_id += 1
           request = {"jsonrpc": "2.0", "id": self._next_id, "method": method, "params": params or {}}
           self._file.write(json.dumps(request) + "\n")
           self._file.flush()
           line = self._file.readline()
           response = json.loads(line)
           if "error" in response:
               raise AslanBrowserError(response["error"]["code"], response["error"]["message"])
           return response.get("result")
       
       def navigate(self, url: str, tab_id: str = "tab0", wait_until: str = "load") -> dict:
           return self._call("navigate", {"tabId": tab_id, "url": url, "waitUntil": wait_until})
       
       # ... all other methods follow this pattern
   ```

   **Async client architecture:**
   ```python
   class AsyncAslanBrowser:
       async def connect(self, socket_path="/tmp/aslan-browser.sock"):
           self._reader, self._writer = await asyncio.open_unix_connection(socket_path)
           self._next_id = 0
           self._pending = {}  # id → Future
           self._read_task = asyncio.create_task(self._read_loop())
       
       async def _read_loop(self):
           while True:
               line = await self._reader.readline()
               msg = json.loads(line)
               if "id" in msg and msg["id"] in self._pending:
                   self._pending[msg["id"]].set_result(msg)
               elif "method" in msg:  # notification
                   # Route to event callback if registered
       
       async def _call(self, method: str, params: dict = None) -> Any:
           self._next_id += 1
           req_id = self._next_id
           future = asyncio.get_event_loop().create_future()
           self._pending[req_id] = future
           request = {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params or {}}
           self._writer.write((json.dumps(request) + "\n").encode())
           await self._writer.drain()
           response = await future
           del self._pending[req_id]
           if "error" in response:
               raise AslanBrowserError(response["error"]["code"], response["error"]["message"])
           return response.get("result")
   ```

   **Connection management:**
   - Retry on connect: 3 attempts with 100ms, 500ms, 1000ms backoff.
   - Context manager: `with AslanBrowser() as browser:` / `async with AsyncAslanBrowser() as browser:`
   - `close()` method that cleanly disconnects.
   - If socket doesn't exist, raise clear error: `ConnectionError("aslan-browser is not running. Start it first.")`

   **Target developer experience (from PRD Section 11):**
   ```python
   from aslan_browser import AslanBrowser

   browser = AslanBrowser()
   browser.navigate("https://github.com/login", wait_until="idle")
   tree = browser.get_accessibility_tree()
   browser.fill("@e1", "myusername")
   browser.fill("@e2", "mypassword")
   browser.click("@e3")
   jpeg_bytes = browser.screenshot(quality=70)
   browser.close()
   ```

6. **Verify (Python-specific):**

   For `package-setup`:
   ```bash
   cd sdk/python && python3 -c "import aslan_browser; print('OK')"
   ```

   For `sync-client`:
   ```bash
   cd sdk/python && python3 -c "from aslan_browser import AslanBrowser; print(dir(AslanBrowser))"
   ```
   Verify all expected methods are present.

   For `async-client`:
   ```bash
   cd sdk/python && python3 -c "from aslan_browser import AsyncAslanBrowser; print(dir(AsyncAslanBrowser))"
   ```

   For `sdk-tests`:
   ```bash
   # Start aslan-browser app first, then:
   cd sdk/python && python3 -m pytest tests/ -v
   ```

   For `benchmarks`:
   ```bash
   # Start aslan-browser app first, then:
   python3 benchmarks/benchmark.py
   ```
   Compare against targets: JS eval <2ms, screenshot <30ms, a11y tree <50ms.

7. **Update state:**
   ```bash
   jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-6-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-6-plan.json
   ```

8. **Update notes.**

9. **Return to step 1.**

### 3. Completion

1. Show final progress:
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-6-plan.json
   ```

2. Verify the complete project:
   - Swift app builds and runs.
   - Python SDK installs and imports.
   - Integration tests pass.
   - Benchmarks run and results are documented.
   - README exists with quickstart.

3. Final checklist:
   - [ ] `xcodebuild build` succeeds
   - [ ] App starts and listens on `/tmp/aslan-browser.sock`
   - [ ] `pip install -e sdk/python/` succeeds
   - [ ] `python3 -c "from aslan_browser import AslanBrowser"` succeeds
   - [ ] Integration tests pass
   - [ ] README is accurate and complete
   - [ ] Benchmark results are recorded

4. Add to `notes.md`: "Phase 6 complete. All 6 phases done. aslan-browser is fully operational."

5. Summarize the entire project:
   - What was built across all phases
   - Performance benchmark results
   - Known limitations
   - Potential future improvements
