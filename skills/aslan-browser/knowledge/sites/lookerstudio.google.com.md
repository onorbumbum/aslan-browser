# Looker Studio / Data Studio

- Public API endpoint is `datastudio.googleapis.com/v1`.
- Public Data Studio API supports asset search and permission management only:
  - `GET /assets:search`
  - `GET/PATCH /assets/{assetName}/permissions`
  - `POST /assets/{assetName}/permissions:addMembers`
  - `POST /assets/{assetName}/permissions:revokeAllPermissions`
- The public API does not expose report internals: pages, charts, filters, dimensions, calculated fields, data source mappings, or data source replacement.
- To diagnose/fix mixed report data sources, browser/UI automation is required unless using unsupported private endpoints discovered from network traffic.
- In edit mode, some report sections are grouped. Selecting a child may show only `Group properties`; use Arrange → Ungroup, then select the actual `.lego-component.simple-table` / `.lego-component.simple-linechart` element to expose chart fields.
- Clicking data cells can trigger chart cross-filtering instead of selection. Prefer dispatching clicks to the component wrapper element (e.g. `.lego-component.simple-table...`) or its header/edge.
- Field chips use `.left-half` for field options/display name and `.right-half` for field replacement picker. For percent-of-total columns, set the underlying metric, open `.left-half`, set Comparison calculation → Percent of total, then set Display name (e.g. `% Sessions`).
- Stale `.cdk-overlay-backdrop` / `.cdk-overlay-pane` elements can block canvas clicks after field dialogs; remove them in eval if Escape does not close them.
- Useful report URLs:
  - View: `https://lookerstudio.google.com/reporting/{reportId}/page/{pageId}`
  - Data Studio legacy host redirects/works: `https://datastudio.google.com/u/0/reporting/{reportId}/page/{pageId}`
  - Reporting home (list owned/shared reports): `https://lookerstudio.google.com/navigation/reporting`
  - Connector gallery (create a data source): `https://lookerstudio.google.com/datasources/create`

## Cloning a report for a new client (Make a copy)
- Full flow: `knowledge/playbooks/lookerstudio-clone-client-report.md`.
- **Create data sources first** (connector gallery), THEN Make a copy. New sources take ~1 min to appear in the copy picker (propagation lag — reopen the dialog if missing).
- Data source name (top-left, "Untitled Data Source") is a `[contenteditable=true]` DIV — set via `execCommand("selectAll")` + `execCommand("insertText", ...)`. `aslan type` fails on values containing `&`.
- **Make a copy** is under the "More report actions" kebab (aria-label) in view mode → `[role=menuitem]` "Make a copy".
- Copy dialog: each row has two `.datasource-selector-wrapper`s (original, new). Map wrappers by index after reading them (`0`=GA orig, `1`=GA new, `2`=SC orig, `3`=SC new for a 2-source report). Click `wraps[i].querySelector("button")` to open that row's picker.
- The picker is a **cdk-overlay OUTSIDE `[role=dialog]`**. Its rows are `.datasource-option`; click via full pointer sequence on the row (`span.mat-mdc-tooltip-trigger` holds the full name → `.closest(".datasource-option")`). Do NOT rely on the dialog's own input to filter — it targets the wrong field; the rows list all sources unfiltered anyway.
- "Copy Report" creates the copy but does NOT navigate your tab to it — find it in the reporting home as "Copy of {template}".
- Report title (top bar, edit mode) is `ng2-editable-label` → click it, then edit inner `contenteditable#ng2-editable-label` via `execCommand insertText`; Enter commits. Beware: a bare `textContent===name` selector matches the `<head><title>` first — scope to `body *` with a top-bar bounding rect.
- Delete a canvas component (e.g. template client's logo): select it, then **right-click → context menu `[role=menuitem]` "Delete"**. The bare Delete key needs canvas keyboard focus and usually no-ops.
- Share: top-bar "Share" button → dialog `input.add-peoples-input` (set value + dispatch `input`) → click the autocomplete `.datasource-option`-style suggestion (`"Name" <email>`) → role defaults to Viewer → "Send". Confirm the email appears under "People with access".
