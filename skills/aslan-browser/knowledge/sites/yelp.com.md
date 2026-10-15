# yelp.com / biz.yelp.com (Yelp for Business)

Login state persists in the user's Aslan tabs. Current client account: We Care Medicare (biz id `74B2PSDksrsfsH6GKGhfFw`), public URL `https://yelp.com/biz/we-care-medicare-baywood-los-osos`. The account also manages two unrelated businesses (Central Coast Speech Pathology, Village Creative) under "See all locations" — these are separate listings, not duplicates.

## Layout / selectors

- Dashboard `https://biz.yelp.com/home/<bizid>`; editable fields at `https://biz.yelp.com/biz_info/<bizid>`; photo manager at `https://biz.yelp.com/biz_photos/<bizid>`.
- Sections on biz_info: Categories and services, Photos and videos, Amenities and more, Hours, From this business (Specialties / History / Meet the owner/manager), Business info.
- "Add history" / "Add intro" labels are plain `<span>`s, not buttons or links. Click their parent container: `sp.closest("[role]") || sp.parentElement`, dispatching the full `pointerdown→mousedown→pointerup→mouseup→click` sequence.
- Category edit dialogs: search input + suggestion menu items keyed by `data-testid="menu-item-<Category Name>"`. Select via full pointer-event sequence on the menu item. Save per dialog; there is one Save/Cancel pair per nested view.
- Amenities dialog: 36 radios = 18 attributes x Yes/No pairs sharing a `name` (`is_women_owned`, `BusinessOpenToAll`, `ByAppointmentOnly`, `accessible_parking`, ...). First radio of a pair = Yes. React radios accept `.click()` on the input node.
- Basic Info dialog (Edit next to business name) only holds name/phone/website. Categories are NOT editable there.

## CRITICAL: save behavior

- **Never reload shortly after clicking Save.** Yelp's saves are async; a reload 3-5s later can abort the PUT and silently drop the change. Wait ≥6s and verify the section text updated in-page before navigating or reloading. Verify real persistence by reloading once more.
- **The "Add a category" dialog submits a stale full category list.** Saving it after a separate edit reverts the earlier edit. Make ONE category change per session, save, and re-verify with a reload before any other edit.
- Dialogs render in a portal, so `aslan text` may not show them. Enumerate with `[role=dialog]` and read `innerText` via eval.

## Known server-side rejections (as of 2026-09-30)

- Adding or switching to category **Health & Medical — Health Insurance Offices** is silently rejected for this insurance-agency listing (dialog closes, no error, list unchanged after reload). Tried: replace slot 1, add as new, replace slot 2, from clean reloads. Categories remain `Insurance > Life Insurance` + `Financial Services > Financial Advising`. Looks like vertical governance / moderation; only Yelp support can resolve.
- Other fields (Specialties, Amenities, Meet the owner) save fine via the same synthetic-event techniques.

## Photo uploads do not automate

- The biz_photos page has a `[data-testid=drag-and-drop-container]` dropzone ("Browse photos or drag here to add") with one hidden `input[type=file]` (multiple, accepts .jpg/.png/...).
- `aslan upload` writes the file and fires `change` (verified: file readable, size correct), and React's handler reads and resets the input — but **no network request is ever issued**. Synthesized `DataTransfer` drop events also ignored. Yelp's dropzone appears to require trusted events.
- Manual fallback: prepare JPEGs locally (`sips -s format jpeg in.webp --out out.jpg` converts the site's webp assets), then have the user drag them onto the dropzone in their browser. Site brand photos for We Care Medicare live in `public/images/` of the site repo.

## Consumer-facing page

- Verify all changes at the public URL (yelp.com/biz/...) — the biz_info overview hides some things (Meet the owner card shows only on the consumer page; `ownerOnPage` string checks on biz_info give false positives because the owner's name appears in Specialties text).
- Consumer page header shows category-derived title, e.g. "WE CARE MEDICARE - ... - Life Insurance - Yelp".
