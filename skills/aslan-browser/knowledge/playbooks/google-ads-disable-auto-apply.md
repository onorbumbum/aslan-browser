# Disable Google Ads auto-apply recommendations

## Inputs

- Exact customer ID whose auto-apply settings are approved for change.
- A selected-account Google Ads UI URL, plus the active browser tab/session.

## Prerequisites

- Explicit approval to disable automatic changes.
- Read ads.google.com site knowledge. Prefer the Google Ads API for supported subscription types.
- Verify the browser header shows the intended client and customer ID before each settings mutation. A manager-account header is not the client.

## Steps

1. Open Recommendations, then Auto-apply settings. Read Maintain your ads and Grow your business selection counts. Capture the current configuration.
2. If bulk Deselect all is used, treat the new checkbox count as unsaved until independently verified. The top toolbar Save workspace button does not save auto-apply settings.
3. If bulk selections do not persist, use the Auto-apply History tab. Its table shows recommendation types and On/Off state.
4. Read the row for the approved recommendation type. Click its first `ess-cell[essfield=status]`, which contains `.aw-status`, not its textual Status cell.
5. Read the popup, then select Disable. It exposes role option with text Disable.
6. Wait for that specific row to read Off. An Off row with no historical applications can disappear from the table. Read-back can lag aslan wait --idle, so verify the exact row or API subscription state before the next change.
7. Repeat only for approved enabled types. Do not enable other settings or apply pending recommendations.
8. Independently query recommendation_subscription through the Google Ads API. UNKNOWN types may have indistinguishable resource names, so do not mutate those resource names through the API.
9. Reload the client UI. Verify Maintain and Grow both show zero selected. Cached counts can lag API changes; a fresh reload and a second API query are stronger evidence than the initial checkbox view.

## Notes

- `ocid` in the UI is not the displayed customer ID. Use the selected-account URL and verify the client header rather than substituting the customer ID into ocid.
- Keep browser actions pinned to the task tab when opening another tab to inspect a destination.
- A Google Ads DOM can contain hidden dialogs and empty drawer Save controls. Do not click hidden buttons or Save workspace as substitutes for a real settings save.
- Current Safari-compatible Aslan builds can load account pages that older builds redirected to browser_not_supported. Do not assume a page loaded or a mutation saved merely because its accessibility tree is populated.
