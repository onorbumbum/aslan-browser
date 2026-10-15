# Vendasta / Listing Builder

## Partner account to Listing Builder

- Partner account detail URL: `https://partners.vendasta.com/businesses/accounts/{ACCOUNT_ID}/details`
- The `Listing Builder | Standard` link points to the SSO gateway:
  `https://sso-api-prod.apigateway.co/service-gateway?serviceProviderId=MS&account_id={ACCOUNT_ID}`
- Navigating to that SSO URL in the current tab lands at:
  `https://{partner}.pdqs.mobi/edit/account/{ACCOUNT_ID}/app/overview`
- Listing Sync URL:
  `https://{partner}.pdqs.mobi/edit/account/{ACCOUNT_ID}/app/listing-sync`
- Business Profile URL:
  `https://{partner}.pdqs.mobi/edit/account/{ACCOUNT_ID}/app/listing-profile`
- Citations URL:
  `https://{partner}.pdqs.mobi/edit/account/{ACCOUNT_ID}/app/citations`

## Listing Sync interpretation

- The table columns are Source, Accuracy Report, Status, Listing Score, Listing Score (max), Last Update, Category.
- Treat `Synced` as sync-connected/live. Split it into `Listing is Accurate` and `Found with possible errors`.
- Treat `Submitted` as pending/unconfirmed, even if a `View listing` URL exists.
- Treat `Sync failed` as unresolved; a public URL does not make the sync successful.
- `View listing` link count is not equivalent to successful sync count.
- `Source does not have reporting` means Vendasta cannot verify accuracy/status from that publisher.
- The Citations page is a separate citation-discovery metric. Do not add its total to Listing Sync totals.

## Extraction

Aggregate current table rows with:

```javascript
const rows = Array.from(document.querySelectorAll("table tbody tr"))
  .map(tr => tr.innerText.trim())
  .filter(t => t.includes("\n") && (t.includes("Synced") || t.includes("Submitted") || t.includes("Sync failed")));
return {
  total: rows.length,
  synced: rows.filter(t => t.includes("Synced")).length,
  submitted: rows.filter(t => t.includes("Submitted")).length,
  failed: rows.filter(t => t.includes("Sync failed")).length,
  accurate: rows.filter(t => t.includes("Listing is Accurate")).length,
  possibleErrors: rows.filter(t => t.includes("Found with possible errors")).length,
  notFound: rows.filter(t => t.includes("Listing Not found")).length,
  noReporting: rows.filter(t => t.includes("Source does not have reporting")).length
};
```

Business Profile textarea values may be omitted from `tree` and `text`; inspect `input,textarea` values with `eval`.

The shared `listing-coverage-report/scripts/extract-listing-sync.js` currently returns `source: ""` for every row (markup changed); statuses, accuracy, and URLs still extract. Get names from row text instead:
`return JSON.stringify(Array.from(document.querySelectorAll("table tbody tr")).map(tr=>tr.innerText.trim().split("\n").map(s=>s.trim()).filter(Boolean)).filter(a=>a.length>2))` (first element is the source name).

The Listing Sync headline (`Syncing progress N/51`, Synced or submitted / Sync in progress / Not syncing) counts primary sources plus Additional Sources; the Additional Sources table alone is 42 rows on the Uzunu Pro + Listing Sync Pro setup.

## Citation Builder data providers

- On `/app/citations`, inspect `.listing-source-header .logo-heading` images to identify data providers. Logos may have empty alt text and be omitted from the accessibility tree.
- `.logo-heading.localeze` identifies Neustar Localeze; `.logo-heading.foursquare` identifies Foursquare. `.neustar-publications` is a downstream publisher group, not additional aggregators.
- Resolve primary-field icons through their `aria-describedby` targets. `check_circle` can mean sent and accepted; `check_circle_outline` can mean only sent. Use the tooltip text rather than assuming both mean synced.
- `View all citations` expands discovered domains and counts. Discovery does not prove who created the citation.

## Keyword Tracking

- URL: `https://{partner}.pdqs.mobi/edit/account/{ACCOUNT_ID}/app/local-seo`.
- Montaire account ID: `AG-VKL8GBK3L3`, partner hostname `uzunu.pdqs.mobi`.
- Add Keywords shows current usage and capacity. Montaire has a 15-keyword limit.
- Global settings control map units, map radius, and root-domain versus full-URL organic matching. Radius choices in miles are 1.25, 2.5, 5, 10, 30, and 50. Radius changes affect competitor inclusion, average rank, and local grid results, not the published service area. Click the nested `.mat-mdc-select-trigger` if clicking the combobox does not open it.
- Delete Keyword removes the term immediately without a confirmation dialog. Preserve unchanged terms rather than deleting and recreating the entire list.
- In Add Keywords, fill the first input, then click `[aria-label="Add keywords"]` to create another input. The bottom Add Keywords button saves all filled rows together. Reload and compare the exact saved set afterward.
- Expand a keyword and select Settings to inspect Favorite Keyword, Sync Keyword, and Delete Keyword. Favorite sends the keyword to executive reports; Sync sends it to listings that accept keywords. Treat keyword replacement as potentially affecting listing content, not only tracking.
- Maps and organic rankings update weekly; difficulty and search volume update monthly. A dash means still searching, not unranked. The UI says searches can take up to 15 minutes.
- The table's Maps Rank is the point rank at the business address. The grid-wide Average Rank only appears after expanding a row (`expand_more` inside the row). Expanding rows in a loop drops some readings; reliable pattern is reload, expand one row matched by exact keyword text in `td.mat-column-keyword`, wait ~5s, then slice `document.body.innerText` from `Your ranking on Google Maps for '<kw>'` (contains Point Rank, Average Rank, STARTED AT values, and `Updated <date>`).
- "To find your listing in Google results, please connect your Google Business Profile" banner means organic ranks stay NR until GBP is connected for tracking; Maps ranks still populate.
- Smart Suggestions can include unrelated statue-shopping terms. Do not accept them without checking service relevance.

## Profile edits

- Check source-specific Google website overrides even if the main website field is correct. Saving the profile distributes data to connected publishers.
- Services appear as readonly `input[data-testid=service-row]` with Remove buttons in their parent wrapper. Add via `input[placeholder="Search or type to add a service"]`, inspect the `mat-option`, then select it. This UI exposes names, not descriptions.
- Service-area Google Places dropdown may ignore clicks and CLI key events. After inspecting suggestions, focus the service-area input and dispatch ArrowDown then Enter keydown/keyup events with `keyCode` and `which` set to 40 and 13. Verify a new `mat-chip-option` appears. Do not assume selecting a suggestion succeeded.
- Description fields are `textarea[placeholder="Short description"]` and `textarea[placeholder="Long description"]`. Unsaved changes persist across profile tabs; save once after review, then reload and verify.

## Executive Report

- The account detail page's `View Executive Report` action calls `window.open` with an SSO URL. If WKWebView blocks the popup, temporarily replace `window.open` to capture the URL, click the action, then navigate to the captured URL.
- The report lands at `https://{partner}.smblogin.com/account/location/{ACCOUNT_ID}/executive-report/monthly`.
- It is a monthly snapshot, not a live mirror of Listing Sync. Its source set and statuses can differ from the current Listing Sync table because it also includes sources such as Google, Bing, Facebook, X, Instagram, and Apple.
- Use the Executive Report for broad client reporting, trends, and Google Business Profile metrics. Use the live Listing Sync table for exact current Yext distribution counts.
- Do not trust `View listing` merely because Vendasta labels a row `Synced` or `Listing is Accurate`. Publisher URLs can return a real 404, a custom 404 with HTTP 200, a generic publisher home page, or an account-claim redirect. Audit the effective destination and visible business record before reporting it as a working public listing.

## Business Profile editing (Listing Builder)

- Tabs are `span.tab` elements: Primary info, Hours, Descriptions, Images, Social, Attributes.
  Switch with `Array.from(document.querySelectorAll("span.tab")).filter(e=>e.innerText.trim()==="Hours")[0].click()`.
  Unsaved edits persist across tab switches; one bottom `Save` commits them all. Exclude dialog
  buttons when clicking it: `filter(x=>x.innerText.trim()==="Save" && !x.closest("mat-dialog-container"))`.
- **Hours** open in a dialog behind the `mode_edit` button. Seven `mat-mdc-slide-toggle-{0..6}-button`
  toggles, index 0 = Sunday through 6 = Saturday. Toggling a day on reveals `Opens at`/`Closes at`
  inputs defaulting to 9:00 AM - 5:00 PM plus an unchecked "Open 24 hours" checkbox. Set times with
  `aslan type` on the input id, then the dialog's own `Save`.
- **Service areas**: the input is `input[placeholder="Enter a location"]` with no `id` (the address
  field shares the placeholder but has an id — filter on `!e.id`). Type the term, wait ~3s, then
  dispatch ArrowDown then Enter as keydown/keyup with `keyCode`/`which` set to 40 and 13. Verify a
  new `mat-chip-option` appeared; clicking the Google Places suggestion directly does not work.
  Cap is 20 chips. Google may normalize a name on save ("Los Osos, CA" becomes "Baywood-Los Osos, CA").
- **Services**: `input[placeholder="Search or type to add a service"]`. Type, wait ~3s, then click the
  `mat-option` that exactly matches or the one containing "as a custom service". The autocomplete
  panel intermittently stops opening after a rapid run of additions - a term that returns nothing can
  succeed after a pause or a reload, so re-check rather than concluding the term is rejected. Always
  clear leftover text from the input before saving.
- **Images**: the gallery input is `input.hidden-file-input` under "Choose images" (multiple). The
  logo and cover inputs do not exist in the DOM until their `Edit` button is clicked; afterwards
  select them by parent text ("main logo" / "cover photo"). **Logo and cover open a "Crop photo"
  dialog after upload that must be saved before the profile Save — skip it and the image silently
  reverts on reload while gallery images persist.** Always reload and check for the "Add main logo" /
  "Add cover photo" placeholder text to confirm.
- Uploading several gallery files back to back drops some; upload one at a time and confirm the
  "Showing N of N" counter between uploads.
- Saving the profile immediately re-triggers Listing Sync against every connected publisher.
- Removing a service-area chip: the chip's only `<button>` is its primary action and clicking it does
  nothing. The remove control is `mat-icon[matchipremove]` inside
  `.mdc-evolution-chip__cell--trailing` — select it as `chip.querySelector("[matchipremove]")`.
  A `querySelector("button,[matchipremove],mat-icon")` matches the wrong element first.
- Changing the Facebook URL from the numeric page-ID form to the vanity URL
  (`https://www.facebook.com/<handle>`) does not break an existing Facebook sync connection; the
  source stayed connected and accurate afterwards.

## Account creation (Partner Center)

- Entry: Home → `Create account` button, or direct URL `https://partners.vendasta.com/business/create`. A pre-search screen checks for existing businesses; an empty result list means no duplicate.
- After choosing Country/region, the address block appears: street input uses Google Places autocomplete and needs the ArrowDown(40)+Enter(13) keydown/keyup trick; City/State/ZIP autofill from the selected place. Suite goes in `Additional address line`.
- Fields are `glxy-form-field` components; accessible names come from `label[for]`, not `aria-label`. Map ids with: `document.querySelectorAll("label[for]")` and read `closest(".label-and-hint").innerText`. Refs from `aslan tree` shift after every section expansion — prefer id/selector targeting.
- Primary/Additional categories are `<category-select>` chip inputs (placeholder `Add category...`). Options render in `.cdk-overlay-pane mat-option` with Vendasta taxonomy paths (e.g. `Professional Services > Commercial cleaning service`; there is no janitorial entry). Click an option by dispatching mousedown/mouseup/click with coordinates.
- Business phone number lives inside a `forms-va-input-repeated` component (`label="EASY_ACCOUNT_CREATE.PROFILE_PANEL.PHONE_NUMBER"`), not a `label[for]` field.
- `Add hours of operation` → `mode_edit` opens a `mat-dialog-container` with one switch per day (Sunday first). Toggling a day on reveals `Opens at`/`Closes at` text inputs defaulting to 9:00 AM/5:00 PM plus an `Open 24 hours` checkbox. The inline hours preview behind the dialog can stay stale ("Closed") — verify state from the dialog/screenshot, not the underlying preview text.
- `Included products & services` pre-checks the free products (Advertising Intelligence, Vibe Beta); they auto-activate on create. Uncheck (click the `mat-checkbox` native control) unless wanted.
- Successful create lands on `https://partners.vendasta.com/businesses/accounts/{ACCOUNT_ID}/details?...`; the account ID is in the URL. The details page shows only core fields (address, phone, website, category, market) — full profile data entered under "Full business profile" is stored but not displayed there.
- Payment methods combobox sits adjacent to Common business names; verify text landed in the intended field when both hold similar values.
- Service-area input in the create form is the id-less `input.pac-target-input` (the address field is also a pac-target-input but HAS an id). `aslan type` with `input[placeholder="Enter a location"]` hits the address field first — tag the service input with a data attribute instead. The create-form service dropdown ignores synthetic keydown/keyup, `aslan key`, synthetic mouse events on `.pac-item`, and stale a11y option refs. The a11y tree listbox labels also go stale after the first selection (shows the previous city). Practical workaround: select the primary city only (fresh tree, `aslan click` the option ref works the first time), then add the rest in Listing Builder where the ArrowDown(40)+Enter(13) trick works.
- Every successful Google place selection rebuilds the form section and reassigns all `mat-input-N` ids — re-scan labels after each selection before filling the next field.
- Listing Builder edition on the order form: the Listing Builder row has an edition combobox; click its `.mat-mdc-select-trigger` to open, choose `Pro` (wholesale $12.00/mo). SM-template products: Listing Builder | Pro + Citation Builder ($5.00/mo) + Listing Sync Pro (Monthly) ($21.25/mo).
- Order flow: `Activate` on the account details page drafts an order. NEVER click `Submit for customer approval` (emails the client) — use `Process order` → Confirm dialog. Activation history then shows "Activated by <partner user>".
- Hours dialog toggles are `button[role=switch]` with `aria-checked` (no input checkbox inside; index 0 = Sunday). `Opens at`/`Closes at` accept `aslan fill` with `7:00 AM`-style strings. Same dialog in Listing Builder Business Profile: inputs are `mat-input-N` pairs per open day (Mon first); fill, click the switch to close a day, dialog `Save`, then the page `Save` outside the dialog. Partner Center `/edit` Hours tab reads the same record, so it is a second verification point.
- Keyword Tracking Add Keywords dialog: rows are plain inputs; fill the last empty input via eval (`value` + `input` event), click `button[aria-label="Add keywords"]` to append a row, footer button `Add Keywords` saves. Success toast: "Keywords updated".

## Edit Business Profile (account business info)

- URL: `partners.vendasta.com/businesses/accounts/{ID}/edit`. Tabs: Primary info, Hours, Descriptions, Images, Social, Attributes. One bottom Save commits all tabs; unsaved edits survive tab switches.
- Timezone field needs dropdown selection (click the `Timezone` combobox via tree ref, click the rendered `option "PDT (America/Los_Angeles) - ..."` ref); typing a raw value silently clears on save. A transient "Required" toast can appear on Save even when the save succeeds — verify persistence on the details page instead of trusting the toast.
- Services form (`business-google-services-form`) adds custom services on Enter and appears to cap around 13 rows — later additions silently clear the input. Remaining services go in Listing Builder after Local SEO activation.
- Payment methods dropdown can render empty option panes; retry later or set via Listing Builder.
- Images: logo/cover file inputs exist only after Edit → menu → "Upload New". The crop dialog opens after injection; it force-crops to a square, so pre-pad wide logos to a square canvas (Pillow) before uploading or the default crop destroys them. After the crop's Save, the page-level Save is still required. An informational "Upload New Image" dialog may stack on top of the crop dialog — Cancel the top one to reach the crop's Save.
