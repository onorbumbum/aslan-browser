# Playbook: Load Google Reviews for a Business

## Inputs

- **business_name**: string (the business to look up)

## Prerequisites

- A tab must be open. If no tabs exist, create one:
  ```bash
  aslan tab:new
  aslan wait --idle
  ```
  Note: `tab:new` does not accept `--wait`. Navigate separately after creation.
- No login required (Google Maps reviews are public)

## Steps

### 1. Navigate to Google Maps

```bash
aslan nav https://www.google.com/maps --wait idle
```

Do NOT use Google Search — go directly to Google Maps. Maps has the reviews panel built in.

### 2. Search for the business

```bash
aslan click "input[name='q']"
aslan type "input[name='q']" "{business_name}"
```

An autocomplete dropdown usually appears. Check the tree for the right suggestion:

```bash
aslan tree | grep -i "{business_name}"
aslan click @eN    # the autocomplete suggestion row
aslan wait --idle
```

If no autocomplete appears, press Enter instead:

```bash
aslan key Enter
aslan wait --idle
```

Clicking the autocomplete suggestion is preferred — it takes you directly to the business page with reviews already loaded.

### 3. Ensure Reviews tab is active

After clicking the autocomplete suggestion, Maps often loads the business page with the Reviews tab already selected and reviews visible. Check first:

```bash
aslan tree | grep -i "review"
```

If you see review content (reviewer names, "More reviews (N)" button), **skip to step 4** — the Reviews tab is already active.

If you only see the business overview, click the Reviews tab:

```bash
aslan tree | grep -i "tab.*review"
aslan click @eN    # the Reviews tab ref
aslan wait --idle
```

### 4. Click "More reviews (N)" to open the full reviews panel

Look for the button with text like "More reviews (184)":

```bash
aslan tree | grep -i "more review"
aslan click @eN
aslan wait --idle
```

### 5. Scroll down to load all reviews

Google Maps lazy-loads reviews — older reviews only appear when you scroll the reviews panel. The scrollable container is `div.m6QErb.DxyBCb`.

Scroll in a loop with 1.5s pauses until no more content loads:

```bash
# Scroll loop — repeat until scrollTop stops changing
for i in $(seq 1 50); do
    result=$(aslan eval 'var el = document.querySelector("div.m6QErb.DxyBCb"); if (!el) return "not found"; var before = el.scrollTop; el.scrollTop = el.scrollHeight; return before + "/" + el.scrollTop;')
    before=$(echo "$result" | cut -d/ -f1)
    after=$(echo "$result" | cut -d/ -f2)
    if [ "$before" = "$after" ] && [ "$i" -gt 3 ]; then
        break
    fi
    sleep 1.5
done
```

**Calibration:** ~20 scrolls for ~190 reviews, ~50 for ~500. The loop exits automatically when scroll position stops changing.

### 6. Expand all truncated reviews

Long reviews are truncated with a "More" button. Click ALL of them in one shot:

```bash
aslan eval 'var btns = document.querySelectorAll("button.w8nwRe.kyuRq"); btns.forEach(b => b.click()); return btns.length + " expanded";'
```

### 7. Extract all reviews

Once all reviews are loaded and expanded, extract structured data:

```bash
aslan eval 'var reviews = []; document.querySelectorAll("div.jftiEf").forEach(function(div) { var name = div.querySelector(".d4r55")?.textContent?.trim() || ""; var stars = div.querySelectorAll("span.hCCjke.google-symbols.NhBTye.elGi1d").length; var date = div.querySelector(".rsqaWe")?.textContent?.trim() || ""; var text = div.querySelector(".wiI7pd")?.textContent?.trim() || ""; var resp = div.querySelector(".CDe7pd .wiI7pd")?.textContent?.trim() || ""; reviews.push({name: name, stars: stars, date: date, text: text, ownerResponse: resp}); }); return JSON.stringify(reviews);'
```

Returns a JSON array. Each object: `{name, stars, date, text, ownerResponse}`.

**Alternative — raw text extraction:** If structured extraction fails (selectors changed), fall back to:

```bash
aslan eval 'var el = document.querySelector("div.m6QErb.DxyBCb"); return el ? el.innerText : "panel not found";'
```

## Known Notes

- **Use Google Maps, not Google Search.** Maps has the reviews panel built in. Google Search results link to Maps anyway — skip the extra hop.
- **Autocomplete click often skips the Reviews tab step.** When you click the autocomplete suggestion, Maps frequently loads the business page with Reviews already active.
- **Scroll is mandatory.** Google lazy-loads reviews. Without scrolling the panel, you only get the first ~10.
- **"More" buttons must be clicked.** Each truncated review has a "More" button (`button.w8nwRe.kyuRq`, `aria-label="See more"`). Click all before extracting.
- **Scroll the reviews panel div, not the page.** The reviews live in `div.m6QErb.DxyBCb` inside the left sidebar.
- **Owner responses use `.CDe7pd` container.** The owner response text is inside `.CDe7pd .wiI7pd`, not a sibling of the review text.

## Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| No reviews panel | Business not found or no reviews | Check search results — may need more specific name |
| Only ~10 reviews visible | Didn't scroll the panel | Run the scroll loop in step 5 |
| Review text is truncated | Didn't click "More" buttons | Run the expand-all in step 6 |
| `div.m6QErb.DxyBCb` not found | Google changed class names | Use `aslan tree` to find the scrollable reviews container |
| Structured extraction returns empty | Selector classes changed | Fall back to raw `innerText` extraction |
| Owner responses all empty | Wrong selector | Check `.CDe7pd .wiI7pd` — Google may change the container class |
