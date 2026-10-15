# projectauditors.com

- Direct `curl` and Jina retrieval may return HTTP 403 or empty content, while Aslan Browser loads the HTTPS site successfully.
- Several pages emit visible PHP warnings from a rate-limited `api.ipstack.com` request before the header.
- The site is legacy PHP and desktop-first. Useful paths:
  - Home: `https://www.projectauditors.com/`
  - About: `https://www.projectauditors.com/Company/About_us2.php`
  - Services by topic: `https://www.projectauditors.com/Consulting/Consultancy_Services_By_Topic.php`
  - Management: `https://www.projectauditors.com/Resume/ResumeHome.php`
  - Contact: `https://www.projectauditors.com/Company/CompanyHome.php`
- `aslan tree` exposes navigation and list text but may omit body paragraphs. Screenshots are useful for reading page copy.
- To recover image URLs when normal HTML/eval output is blank, set `document.title` to an image `src` with `aslan eval`, then read it with `aslan tabs`.
