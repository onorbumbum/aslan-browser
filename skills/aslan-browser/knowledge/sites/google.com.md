# Google Search — Site Knowledge

## SERP Scraping

- Result links include `#:~:text=` fragment anchors ("Read more" links)
- These resolve to the same page as the canonical result → causes duplicate tabs when opening all links
- Filter them out in JS:
  ```js
  if (href.includes('#:~:text=')) continue;
  ```
- Or in Python after collecting URLs:
  ```python
  from urllib.parse import urldefrag
  href, _ = urldefrag(href)
  ```

## Google Maps — downloading place/Street View photos

- A bare `@lat,lng,3a,...` URL falls back to satellite 3D view. To get Street View, open the place page (`/maps/place/?q=place_id:...`), then click the button whose aria-label is exactly `Street View & 360°`. The resulting URL contains the panoid and a ready `streetviewpixels-pa.clients6.google.com/v1/thumbnail?...panoid=...&yaw=...` URL.
- `streetviewpixels` thumbnail URLs 403 from `curl` (PERMISSION_DENIED JSON) but work from an in-page `fetch(..., {credentials:"include"})` via `aslan eval`. Return as a data URL (FileReader → base64) and decode locally; bump `w`/`h` params for resolution (e.g. `w=1200&h=700` returns 1024px wide).
- Place-page gallery thumbnails mix review photos of other businesses; verify each candidate visually before using one as a venue reference.
