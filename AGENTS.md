# Aslan Browser

## Learned Patterns
- Xcode build metadata can capture environment credentials. Keep every `.build-*` directory out of Git.
- For a branch-only history-cleanup push from a mirror clone, pass `-c remote.origin.mirror=false` before `push` so an explicit refspec and force-with-lease work.
