# Vendasta keyword tracking

## Inputs
- Business account ID and partner host, verified from Partner Center.
- Keywords grounded in current services and target locations.

## Prerequisites
- Authenticated Partner Center browser session.
- Use a new tab with explicit `--tab` arguments if another agent uses the browser. Verify it exists before navigating.

## Steps
1. Open the account in Partner Center. Read the Listing Builder link's href and navigate through that SSO gateway in the owned tab.
2. Confirm the business name and address. Click Keyword Tracking. Its route is `/edit/account/{ACCOUNT_ID}/app/local-seo`.
3. Read current keywords, ranks, update schedule, and the expanded local grid. Extract keywords with `document.querySelectorAll("td.mat-column-keyword")`.
4. Open Add Keywords to inspect capacity. Do not assume unlimited slots. Uzunu Pro had 15 slots.
5. Inspect the page-level Settings dialog for Maps radius and organic full-URL setting. Do not change these incidentally. Radius changes affect competitors and rank comparability.
6. In Add Keywords, fill the first input. Click `button[aria-label="Add keywords"]`, labeled visually as Add a keyword..., to create another input row. Inspect new input IDs after each addition. Each keyword needs its own row.
7. Review input values. Click the footer Add Keywords button to save. The inner Add a keyword... button only creates another input row.
8. Confirm Keywords updated, reload, and extract the persisted keyword list. New keywords show pending dashes rather than immediate ranks.

## Notes
- Maps and organic ranks update weekly; difficulty and volume update monthly.
- A city-qualified keyword does not expand or relocate the configured local grid. Point rank is not county-wide rank.
- Preserve existing history unless keyword deletion is approved. Flag misspellings and low-relevance terms for replacement.
- To remove an approved keyword, expand its row, select the row's Settings radio, then click Delete Keyword. Deletion takes effect immediately without a confirmation dialog.
- Radius dropdown options in miles are 1.25, 2.5, 5, 10, 30, and 50. If clicking the combobox does not open it, click its `.mat-mdc-select-trigger` child. Apply saves the radius; allow up to 15 minutes for all keyword grids to update. Reopen Settings after a reload to verify persistence.
- Use scoped selectors or fresh tree refs. An unscoped `button` selector can open account notification controls.
- Uzunu account ID is `AG-R7WKNPFS2G`, partner host `uzunu.pdqs.mobi`. Confirm identity on each visit.
- Michael Harris account ID is `AG-SWN82XPQ3Q` on the same partner host. Its Avila Beach listing has 15 keyword slots. Check the configured radius before describing SLO-qualified keywords as coverage across San Luis Obispo; a small Avila Beach grid does not measure the whole city.
