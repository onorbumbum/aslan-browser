# Release Notes — aslan-browser

## 2026-02-23: SDK __version__ drift

`sdk/python/aslan_browser/__init__.py` has a `__version__` string that the CLI reads for `aslan --version`. This was NOT in the release config's version locations, so it drifted — pyproject.toml was at 0.5.0 but `__init__.py` was stuck at 0.3.0. Fixed by adding it to the version locations table. Both pyproject.toml AND `__init__.py` must be bumped together.
