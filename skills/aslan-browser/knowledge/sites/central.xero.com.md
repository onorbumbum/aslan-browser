# Xero Central

- Official help pages under `/0/article/<slug>` render their article content in nested shadow roots. Toolshed url-to-markdown may return no convertible content.
- `aslan text` reads expanded article sections but can omit collapsed section bodies. `aslan tree` exposes their content. For complete source verification, recursively collect `textContent` from nested shadow roots. Deduplicate repeated article text when saving excerpts.
- Source links are also inside shadow roots. Recursively collect anchors instead of relying on `document.querySelectorAll("a")`.
