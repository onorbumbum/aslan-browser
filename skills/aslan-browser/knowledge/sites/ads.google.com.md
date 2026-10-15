# ads.google.com

- Standard Google Ads account pages can redirect Aslan's WKWebView to `/aw/browser_not_supported`. Use the `google-ads` skill/API for account diagnostics and mutations instead of trying to bypass this page.

## Local Services Ads

- LSA account picker can show duplicate business names. For DWCA, the correct LSA account is the second "Dutch Window Cleaning Artist" entry; its URL params include `cid=4750952834&bid=5644205680&euid=5640684730`, and the drawer footer shows customer ID `6039517852`.
- The first DWCA-looking account may show no leads and a payment issue; that is the wrong account for DWCA LSA reporting.
- LSA Reports URL pattern:
  `https://ads.google.com/localservices/reports?cid=4750952834&bid=5644205680&pid=9999999999&euid=5640684730&hl=en&gl=US`
- If clicking drawer item "Reports" changes the URL but content still shows Leads, run `aslan reload`, then read the page again.
- Reports page exposes totals in text: Total lead spend, phone/message spend, charged leads, phone/message lead counts, ad impressions, top impression rate, absolute top impression rate.
- LSA date presets may not respond to a plain `aslan click`. Open the date menu, find the visible `[data-value=this_month]` or `[data-value=last_month]` element, dispatch `pointerover → mouseover → mouseenter → pointerdown → mousedown → pointerup → mouseup → click`, then wait about 20 seconds before reading. The old totals can remain in the DOM during the async refresh, so verify the displayed date line and totals after the wait.
- Leads page URL pattern:
  `https://ads.google.com/localservices/inbox?cid=4750952834&bid=5644205680&pid=9999999999&euid=5640684730&hl=en&gl=US`
- Leads table pagination is custom spans, not real visible buttons. The next-page control is `[data-paginate=next]`; dispatch full mouse events if `.click()` does not work.
