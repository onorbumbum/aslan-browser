# Playbook: Clone a Looker Studio report for a new client

Duplicate an existing YouGrow client dashboard, remap it to a new client's data sources, rebrand, and share. Signed into the agency Google account that owns the data (e.g. danabeyin@gmail.com).

## Inputs
- Template report ID (e.g. `784a6b40-...` = "CC Red Coral Spa Google Analytics Report", GA4 + Search Console).
- New client's GA4 account + property, and Search Console site (URL-prefix or sc-domain).
- Client business name, client Google email.

## Prerequisites
- The client's GA4 property and GSC property already exist and the agency account can access them.
- Use an isolated session: `export ASLAN_SESSION=looker` and `aslan tab:new` (never navigate the user's tab0).

## Steps

1. **Create the GA4 data source.** `aslan nav https://lookerstudio.google.com/datasources/create`. Click the "Google Analytics" connector card. Click the account (leaf element, exact text). Click the property (exact text). Rename the `[contenteditable=true]` "Untitled Data Source" title to `"<Business> - GA4"` via `execCommand selectAll`+`insertText`. Click `CONNECT`. Note the `datasources/<id>` URL.

2. **Create the Search Console data source.** Back to `.../datasources/create` → "Search Console" card → click the site (exact URL text) → in the Tables column click **"Site Impression"** (query-level) → rename to `"<Business> - Search Console"` → CONNECT.

3. **Wait ~1 min** for the new sources to propagate to the copy picker. Confirm they appear under Reporting home → Data sources. Then fully reload the template report route before opening Make a copy. Reopening a picker on an already-loaded report can keep a stale source list and stack duplicate overlays.

4. **Open the template & Make a copy.** `aslan nav .../reporting/<templateId>`. Click "More report actions" (aria-label) → `[role=menuitem]` "Make a copy".

5. **Remap each row.** Read `[role=dialog] .datasource-selector-wrapper` list; map by index (`1`=GA new, `3`=SC new for a 2-source template). For each: click `wraps[i].querySelector("button")`, then in the cdk-overlay picker click the `.datasource-option` whose `span.mat-mdc-tooltip-trigger` text is the client's source (`row.closest(".datasource-option")`, full pointer sequence). Screenshot to confirm the New Data Source column updated. Click **"Copy Report"**.

6. **Find the copy.** It does NOT open automatically. `aslan nav https://lookerstudio.google.com/navigation/reporting`, find `a[href*="/reporting/"]` titled "Copy of <template>". Open its `/edit` URL.

7. **Verify data wiring.** The right Data panel should list the client's two sources; GA scorecards read "No data" if the property is brand-new (correct).

8. **Rename.** Click the `ng2-editable-label` title (scope selector to `body *` in the top bar — a bare text match hits `<head><title>`), edit inner `contenteditable#ng2-editable-label` via `execCommand insertText` to `"<Business> Google Analytics Report"`, press Enter.

9. **Remove the template client's logo.** Find `.lego-component.image-component`; the one with the larger `left` (top-right) is the template's logo (keep the left/UZUNU one). Select it, **right-click → Delete**.

10. **Share with the client.** Top-bar "Share" → set `input.add-peoples-input` value to the client email + dispatch `input` → click the `"Name" <email>` autocomplete suggestion → role = Viewer (default) → "Send" → confirm it appears under "People with access". Autocomplete may show a saved contact whose address is not linked to a Google account. After Send, inspect the dialog for a warning before treating the share as successful.

## Notes
- Public Looker API can't do any of this — UI only.
- The copy-dialog picker is a cdk-overlay outside `[role=dialog]`; click `.datasource-option` rows directly, don't fight the search inputs.
- `aslan type` breaks on `&` in values — use `execCommand insertText` for names with ampersands.
