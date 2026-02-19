# Notes

Runtime discoveries, edge cases, and gotchas found during implementation. Updated by agents across all phases and sessions. Always loaded into context at session start.

## Phase 1

### AppKit Lifecycle with `@main` (Critical)
The `@main` attribute on `NSApplicationDelegate` generates a call to `NSApplicationMain()`, but without a main nib file, the delegate is never connected. **Fix:** Override `static func main()` to manually create `NSApplication.shared`, set the delegate, and call `app.run()`. This is required for any nib-less AppKit app.

### `NSPrincipalClass` Required
The auto-generated Info.plist from a SwiftUI template doesn't include `NSPrincipalClass`. Added `INFOPLIST_KEY_NSPrincipalClass = NSApplication` to both Debug and Release build settings.

### App Sandbox Blocks `/tmp/` Writes
With `ENABLE_APP_SANDBOX = YES`, the app can't write to `/tmp/` directly. Use `NSTemporaryDirectory()` instead, which resolves to the sandbox container: `~/Library/Containers/com.uzunu.aslan-browser/Data/tmp/`. For Phase 2's Unix socket at `/tmp/aslan-browser.sock`, the sandbox will need a file access exception, or we may need to disable sandbox.

### Entitlements for Network Access
Created `aslan-browser/aslan_browser.entitlements` with `com.apple.security.network.client = true` to allow WKWebView to make outgoing network requests.

### `WKNavigationDelegate.didFinish` Title Timing
When `didFinish` fires, `webView.title` may be empty string (not yet parsed from `<title>`). The JS eval `document.title` returns the correct value. This is expected — title becomes available shortly after didFinish.

### Sync Conflict Files
Syncthing (or similar) can create `.sync-conflict-*.swift` files in the source directory. These get auto-synced into the Xcode project via `PBXFileSystemSynchronizedRootGroup` and cause build failures due to duplicate type definitions. Delete them immediately.

Phase 1 complete. App launches with AppKit lifecycle, BrowserTab loads pages, navigate/evaluate/screenshot working.
