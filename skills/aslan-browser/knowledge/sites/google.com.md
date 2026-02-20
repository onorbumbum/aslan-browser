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
