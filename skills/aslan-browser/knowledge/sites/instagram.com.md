# Instagram — Site Knowledge

## Search

- Search input is React-based — `fill()` just sets `.value` without triggering React state updates
- Suggestion dropdown won't populate unless React detects the input
- Must use `execCommand("insertText")` via evaluate:
  ```js
  var input = document.querySelector('input[type="text"]');
  input.focus();
  input.value = '';
  document.execCommand("insertText", false, "search query");
  ```
- Wait 2-3 seconds after typing for suggestion dropdown to appear

## Profile Research

- When logged in, `aslan text` on a public profile often exposes the useful basics directly: username, full name, bio, category, post count, follower count, following count, and external link
- For richer structured profile data without opening posts one by one, Instagram's web endpoint works:
  `https://www.instagram.com/api/v1/users/web_profile_info/?username=<handle>`
- Send header `x-ig-app-id: 936619743392459` plus a normal browser `user-agent`
- The response includes biography, profile image, bio links, and `edge_owner_to_timeline_media.edges` with recent post/reel thumbnails and captions when available

## Public Post Content Without Login (2026-09-22)

- Post pages and `url-to-markdown` hit the login wall for non-profile post URLs.
- Caption: `https://www.instagram.com/p/<ID>/embed/captioned/` loads in Aslan without login and shows username, date, likes, and the full caption text.
- Carousel photos/video: snapinsta.to — paste the post URL, click Download, then collect each resolution `<select>`'s `value` via eval (`document.querySelectorAll("select")` → `s.value`). The dl.snapcdn.app tokens expire ~1 hour after issuance; curl them immediately. Selected option value is the largest available size per image.

## Location (place) lookup — what the Story location sticker sees

- `GET /api/v1/location_search/?latitude=<lat>&longitude=<lng>&search_query=<q>` (fetch from an instagram.com tab, headers `x-ig-app-id: 936619743392459`, `x-requested-with: XMLHttpRequest`, `credentials: "include"`) returns `venues[]` with `name`, `external_id` (Facebook Places id), distance and address. Omit `search_query` to get the "nearby" list. This is the decisive test for "my business doesn't show as a location": run it from the business's own coordinates with several name variants.
- `/web/search/topsearch/` returns `places: []` for every query on web — useless for place checks.
- `/explore/locations/<id>/` only accepts Instagram location pks; a Facebook Page ID returns "Something went wrong".
- Keep evals single-line and query one search term per call; batched `Promise.all` over several queries threw a bare "JavaScript error".
- For Facebook-sourced places the Instagram location pk equals the Facebook Page ID, so `/explore/locations/<FB Page ID>/` loads when Instagram knows the place (verified with Village Creative). "Something went wrong" on a Page whose Graph `place_type` is `PLACE` means Instagram has no location record for it yet.
- Creating an Instagram location for a Facebook Page that Instagram doesn't know yet: create (do not publish) a media container with `POST /<ig-user-id>/media` `image_url=<public JPEG>&location_id=<FB Page ID>` using the toolshed Meta token. Meta validates the ID (`(#100) Param location_id is not a valid location page ID` for bad IDs), and a successful container makes `/explore/locations/<FB Page ID>/` resolve within minutes. It does not put the place into `location_search` right away. Unpublished containers expire after 24 h.
