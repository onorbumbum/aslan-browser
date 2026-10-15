# developers.vendasta.com

- Vendasta Developer Center uses Stoplight inside the page. `aslan text` may show only section names until a sidebar group is expanded.
- Local SEO REST API docs live at `https://developers.vendasta.com/platform/3e983aa32af87-local-seo-rest-ap-is`.
- To reveal Listing Profile endpoints, click the sidebar group via DOM eval:
  ```bash
  aslan eval 'return Array.from(document.querySelectorAll("div[title=\"Listing Profiles\"]"))[0].click(), "clicked"'
  ```
- Then click endpoint rows by exact text:
  ```bash
  aslan eval 'return Array.from(document.querySelectorAll("a,div")).filter(e=>(e.innerText||e.textContent||"").trim()==="Update Listing Profile")[0].click(), "clicked"'
  aslan eval 'return Array.from(document.querySelectorAll("a,div")).filter(e=>(e.innerText||e.textContent||"").trim()==="Get Listing Profile")[0].click(), "clicked"'
  ```
- Listing Profile API findings:
  - Base URL: `https://prod.apigateway.co/products/listings`
  - GET/PATCH: `/listingProfiles/{id}`
  - Status: Trusted Tester
  - Requires active Local SEO, OAuth Bearer token, `Accept: application/vnd.api+json`, and for PATCH `Content-Type: application/vnd.api+json`.
  - Listing profile `id` is currently the same as a `platform/salesAccounts` or `platform/businessLocations` id.
