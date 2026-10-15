# Aslan Browser

## Learned Patterns
- Verify OpenRouter key revocation with `/api/v1/key` or `/api/v1/credits`; the legacy `/api/v1/auth/key` endpoint may still return 200 after deletion.
- Xcode build metadata can capture environment credentials. Keep every `.build-*` directory out of Git.
- For a branch-only history-cleanup push from a mirror clone, pass `-c remote.origin.mirror=false` before `push` so an explicit refspec and force-with-lease work.
