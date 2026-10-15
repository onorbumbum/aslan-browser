# adstransparency.google.com — Google Ads Transparency Center

Public, non-personalized record of any advertiser's running ads. No login needed. Useful for verifying a prospect/competitor's ad activity independent of personalization.

## Direct URL patterns

- Domain search: `https://adstransparency.google.com/?region=US&domain=<domain>` — lands directly on results for all advertisers pointing at that domain.
- Region param: `region=US` (or `anywhere`).

## Page structure

- Results grid: ad cards appear in tree as `link/button "Advertisement (N of M)"`. Click the **button** ref to open detail.
- Summary view shows 4 cards + `button "See all ads"` → expands to full grid. After `aslan back` from a detail page you land on the SUMMARY view again — must re-click "See all ads" to reach cards 5+.
- Ad detail page shows: **Last shown** date, **Format** (Text/Image/Video), **Ad funded by** (legal payer name — reveals DIY vs agency), variation count ("1 of N variations"). Creative renders below.
- Card count can render doubled (e.g. "16 of 16" for 8 ads) right after "See all ads"; re-reading the tree later shows the true count.

## Gotchas

- Filter dropdowns (All formats / All platforms / date) do NOT open via tree-ref clicks — likely shadow DOM. Faster to open each ad's detail page for format info than to fight the filters.
- Ad creative text is NOT in `aslan text` on the grid (rendered in canvas/iframe-like cards) — use `aslan shot` to read creatives, or open detail pages.
- No impression/reach/spend data anywhere — existence, format, recency, and payer only.
