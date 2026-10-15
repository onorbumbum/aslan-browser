# us.davines.com

## All Products collection scraping

- URL: `https://us.davines.com/collections/all-products`
- Product cards are `article.product-wrap`.
- The "Load More Products" control is an anchor with selector `.load-more__btn`; clicking it appends more products in-place and advances its `href` (`?page=2`, `?page=3`, etc.).
- After the last page, `.load-more__btn` is removed.
- For an authoritative current collection list, keep clicking `.load-more__btn` until it is removed, then collect the unique `/products/{handle}` links from the loaded `article.product-wrap` cards.
- `/products.json?limit=250&page=N` exposes a broader store feed that can include hidden or legacy products not present in the All Products collection. If using it for compact product/variant data, filter its results to the handles collected from the fully loaded collection first.
- A product's public `/products/{handle}.js` endpoint returns its current title, variants, SKUs, availability, and prices and is useful for spot checks or changed-product deltas.
- Product card fields:
  - Title/description: `.product-info__caption .title` and `.product-info__caption .description`
  - Product URL: first `a[href*="/products/"]` in the card
  - Price: first visible text line matching `$...`, or `product-price` attribute on the nonzero `[product-price]` element
  - Unit price: visible text line matching `($.../... )`
  - Main image: `img` inside the card excluding badge images/classes/parents containing `badge`; prefer `data-srcset` candidate around `600w` over `currentSrc` because lazy-loaded offscreen items may use tiny `50x` images
- Cookie banner can appear first; accepting it is fine and does not affect product DOM extraction.

## Product detail page scraping

There are at least two PDP templates.

New PDP template:
- Short description: `.product-short_description`
- Full description: `#product-description`
- Gallery images: `img[id^="product-gallery-image-"]` (use `src`/`data-src`; avoid related-products images)
- Benefits: `.pdp-specifics__benefits`
- Ingredients: `.pdp-specifics__ingredients .specifics__list.ingredients` (remove trailing `Glossary`/PAO noise)
- How to use: `.pdp-specifics__how-to .specifics__list` (remove `watch the video` CTA)
- Packaging components: `.pdp-specifics__packaging .specifics-packaging__block`, with part/material/recyclability in `.specifics-packaging__pack-text`, `.specifics-packaging__packing-text`, `.specifics-packaging__material-text`

Older/set PDP template:
- Full description fallback: `.product-info-container .description`
- Main product image fallback: `.product_section .product-left-side .image__container img`; do **not** use broad `.product_image img` because it also catches "You may also like" product images.
- Benefits fallback: `#benefits_info .specifics__list` or `#benefits_info`
- How-to fallback: `#how_to_info .specifics__list` or `#how_to_info`
- Ingredients fallback: `#ingredients_info .specifics__list.ingredients` or `#ingredients_info`
