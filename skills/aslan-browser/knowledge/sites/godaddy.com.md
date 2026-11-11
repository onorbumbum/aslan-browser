# GoDaddy (dcc.godaddy.com / sso.godaddy.com)

## Delegate access
- Client accounts shared with Onur are listed at `https://account.godaddy.com/access` (redirects to `sso.godaddy.com/access`) under "Accounts I can access". Each card has an "Access now" link; clicking it lands on `dcc.godaddy.com/control/portfolio?del_code=1` with a blue "onur logged in as: <client>" banner.
- Navigating directly to `dcc.godaddy.com/control/portfolio/<domain>/settings?tab=dns` while in Onur's own account shows "No matches found". Switch into the client account first.
- Leaving the dcc pages (e.g. to `account.godaddy.com/products`) drops the delegate session. Re-enter via the access page.

## DNS record editor: automation does not save
- Inline record edit (row Edit button) shows inputs `#dataDnsFieldInput` (Value), `#nameDnsFieldInput`, `#dnsRecordIdDropdown`, `#ttl`, `#ttlCustomNumber`.
- Neither `aslan type`, select-all + type + Tab, nor React's native value setter with input/change events registers the new value. On Save the field reverts to the stored value and the record saves unchanged. Verify with `dig +short @ns77.domaincontrol.com <domain> A`, not the page.
- Never `aslan click 'button[type=submit]'` here: it matches a different submit button and navigates out of the delegate session.
- Practical rule: have Onur make GoDaddy DNS edits by hand, then verify against the authoritative nameservers.
