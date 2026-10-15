# Dutch Window Cleaning Artist

## Quote form inspection

- `/quote/` redirects to `/quote`, preserving UTM parameters.
- HubSpot renders the form inside `#hs-form-iframe-0`, with an empty src and accessible same-origin contentDocument. The main accessibility tree omits the form fields.
- Read fields with `document.querySelector("#hs-form-iframe-0").contentDocument.querySelectorAll("input,select,textarea")`.
- Read the embed definition URL from resource timing, matching `/embed/v3/form/`. Its JSON contains `form.redirectUrl`, fields, published state and captcha settings.
- After an approved test, reconcile the HubSpot success callback, thank-you submissionGuid, notification email and GA4 realtime quote_sent event before considering any retry. A notification delivered to Onur does not establish delivery to Chas.
- Never submit a test enquiry without separate approval. Do not load the thank-you page in a browser merely to inspect it, since it fires a Google Ads conversion on page load. HTTP retrieval without JavaScript can inspect its response and redirects.
