# Aslan Browser

## Learned Patterns
- Verify OpenRouter key revocation with `/api/v1/key` or `/api/v1/credits`; the legacy `/api/v1/auth/key` endpoint may still return 200 after deletion.
- Xcode build metadata can capture environment credentials. Keep every `.build-*` directory out of Git.
- For a branch-only history-cleanup push from a mirror clone, pass `-c remote.origin.mirror=false` before `push` so an explicit refspec and force-with-lease work.
- Never execute the Aslan binary to read its version (`aslan-browser --version` launches a full instance that unlinks and rebinds `/tmp/aslan-browser.sock`, orphaning the running browser's socket). Read `CFBundleShortVersionString` from Info.plist; run test builds with a short `ASLAN_SOCKET_PATH` (e.g. `/tmp/aslan-pwtest.sock`; long scratchpad paths fail with unixDomainSocketPathTooLong).
- Password fill uses the Bitwarden CLI (`PasswordManager.swift`): GUI launches lack the shell PATH, so it resolves `~/Library/pnpm/bw` and the newest nvm node explicitly; the session key is memory-only and fill is UI-only (never exposed over JSON-RPC).
