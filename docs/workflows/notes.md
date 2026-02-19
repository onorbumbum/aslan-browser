# Notes

Runtime discoveries, edge cases, and gotchas found during implementation. Updated by agents across all phases and sessions. Always loaded into context at session start.

---

## Phase 1 — Skeleton

**Status:** Complete ✅

### Discoveries

1. **Nib-less AppKit lifecycle requires custom `static func main()`** — `@main` on `NSApplicationDelegate` calls `NSApplicationMain()`, which only connects the delegate via a main nib. Without a nib, override `static func main()` to create `NSApplication.shared`, set the delegate, and call `app.run()`. Updated in conventions.md §5.

2. **`NSPrincipalClass` must be set explicitly** — SwiftUI template's auto-generated Info.plist omits it. Added `INFOPLIST_KEY_NSPrincipalClass = NSApplication` to both Debug and Release build settings in the Xcode project.

3. **App Sandbox remaps `/tmp/`** — `ENABLE_APP_SANDBOX = YES` redirects `/tmp/` to `~/Library/Containers/com.uzunu.aslan-browser/Data/tmp/`. Use `NSTemporaryDirectory()` for temp file writes. The Unix socket path `/tmp/aslan-browser.sock` will conflict with sandbox in Phase 2.

4. **`com.apple.security.network.client` entitlement required** — Without it, WKWebView silently fails to load any URL under sandbox.

5. **`webView.title` may be empty at `didFinish` time** — Title is parsed after the navigation delegate callback. Use `document.title` via JS eval for reliable title retrieval immediately after navigation.

6. **Sync conflict files break builds** — Syncthing `.sync-conflict-*.swift` files get auto-included by `PBXFileSystemSynchronizedRootGroup`, causing duplicate type errors. Delete on sight. Consider adding a `.gitignore` or `.stignore` pattern.

### Phase 2 Considerations

- **Sandbox vs Unix socket**: Must decide whether to disable sandbox, use a socket path inside the container, or add a sandbox exception. This is the first decision for Phase 2.
- **Smoke test removal**: The `runSmokeTest()` method in AppDelegate should be replaced by socket server startup in Phase 2.
- **`BrowserError` enum**: Already defined in `BrowserTab.swift` with cases `navigationFailed`, `invalidURL`, `javaScriptError`, `screenshotFailed`. Phase 2 will map these to JSON-RPC error codes.
