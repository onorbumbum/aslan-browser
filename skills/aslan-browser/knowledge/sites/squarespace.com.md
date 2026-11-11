# Squarespace admin

## Read-only commerce inspection

- Products & Services > Products separates Physical, Services, Downloads and Gift Cards into tabs. Inspect the relevant tab and its pagination count before declaring a product absent. Service products can show finite inventory as well as unlimited stock.
- Finance > Payment Settings opens the Selling / Payments settings overlay. A promotion to switch to Squarespace Payments does not mean no processor is connected. Read the existing processor section, which may say Stripe Connected and primary.
- Do not toggle Enable test mode as an inspection step. The UI warns that it disables the store while enabled.
- The commerce overview's past-30-days order count is not proof of whether the client sells elsewhere. Do not copy customer names or emails into evidence when only aggregate sales activity is needed.

## Hidden service drafts

- Add product > Service opens an unsaved Draft. Save opens options Publish, Save as Hidden and Schedule. Choose Save as Hidden explicitly; do not assume the Save button itself saves privately.
- Disable Unlimited and set finite Stock to 0 for an unavailable-for-sale draft. Hidden alone is not a substitute for locking inventory. Reload the list and reopen the editor to verify Hidden, zero stock, price and terms before reporting.
- Product-name clicks in inventory start inline name editing, not the full editor. Use the row's `[data-test=overflow-menu-button] svg` click event, then `[data-test=open-product-composer-button]` for Edit. SVG nodes may need `dispatchEvent(new MouseEvent("click", {bubbles:true}))` rather than `.click()`.
- React Product name and Price can ignore `aslan fill`. Set through the native HTMLInputElement value setter with bubbling input/change events, then verify saved values after reopening. Description is a contenteditable textbox and supports `aslan type`.
- Saved product dialogs retain the generic inventory URL. Their Marketing section shows the exact assigned product URL; return it with the inventory URL and SKU rather than inventing a product-specific admin link.
