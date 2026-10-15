# Google Search Console

## Indexing reports

- Read the property picker options to obtain exact property IDs. Do not infer domain versus URL-prefix ownership.
- The indexing overview URL is `https://search.google.com/search-console/index?resource_id=<encoded-property-id>`.
- Reason rows are actual `tr` elements. A targeted click can use `Array.from(document.querySelectorAll("tr")).find(row => row.innerText.startsWith("<observed reason>")).click()`.
- After clicking a reason, `aslan wait --idle` can finish before the drilldown replaces the overview. Read again until the reason heading and Examples table appear; do not click another reason against stale content.
- Drilldowns show First detected, affected-page count, example URLs, and last crawl dates. Compare those dates to deploy dates rather than treating the email delivery time as incident onset.
- The Examples table defaults to 10 rows. Do not claim all affected URLs were inspected when only the first page was read.
- Do not click Validate fix merely because a current page returns 200. First establish whether the exclusion is intentional and whether all affected examples were corrected.

## Videos enhancement report (rich-result issues)

- Report URL: `https://search.google.com/search-console/r/videos?resource_id=<encoded-property-id>`. The "Fix ..." button in GSC emails is a `https://c.gle/...` link that redirects to this report; `aslan nav` on the c.gle href works (read it with `document.querySelector("a[href^=\"https://c.gle/\"]").href`).
- Issue rows are `tr` elements; click the row via `Array.from(document.querySelectorAll("tr")).find(r => r.innerText.includes("Missing field") && r.innerText.includes("<field>")).click()` to open the drilldown.
- The drilldown's VALIDATE FIX button appears in `aslan tree` as `button "validate fix"`; a plain `aslan click @eN` works but takes ~10s of "Performing quick initial validation" dialog before the status flips to "Validation started / Started: <date>". Read the status block via `aslan text` with enough chars (sidebar text comes after content).
- Validate each issue separately; critical and non-critical issues each have their own drilldown and button.

## Request indexing

- Inspect using `input[aria-label="Inspect any URL in <domain>"]`. After setting its value, dispatch a bubbling `input` event and a bubbling `keydown` KeyboardEvent with `key:"Enter", code:"Enter", keyCode:13, which:13`. Native CLI Enter may not submit this field.
- Read the resulting URL Inspection page and confirm the exact URL before clicking `[aria-label="Request indexingRequest again"]`.
- The request performs a live indexability test. Wait until the dialog explicitly says "Indexing requested" and "URL was added to a priority crawl queue". A click or a testing dialog alone is not confirmation.
- Dismiss the confirmation, then read the page again before inspecting another URL. The dismiss action can trigger a delayed rerender that clears an input filled immediately afterward.
- Requests do not guarantee indexing. Do not resubmit an already confirmed request in the same run.

## Users and permissions page

- URL: `https://search.google.com/search-console/users?resource_id=<encoded-property-id>`.
- The users table lists delegated users plus your own `(you)` row; your row shows a "Verified" badge when your access is token-based. Token-verified owners other than the signed-in user get NO row here — don't conclude someone lacks access from this table alone.
- Two extra controls sit beside ADD USER: "Ownership history" (event log of every verification/delegation/reverification-failure, with method and email) and "Unused ownership tokens" (tokens found for the property that no longer map to a visible owner, with a Remove button).
- Removing an unused token: click Remove in the tokens table, then a dialog appears with CANCEL / VERIFY REMOVAL. After confirming, the row shows "Token successfully removed" and the Site Verification API owners list drops that account immediately.
- API `webResource.get`/`insert` `owners` lists every owner regardless of how ownership was obtained (delegated or token-verified) — cross-check it against the users page to find hidden token-verified owners.
