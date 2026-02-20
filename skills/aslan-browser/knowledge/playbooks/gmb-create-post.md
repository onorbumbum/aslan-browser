# Playbook: Create Google Business Profile Post

## Inputs

- **text**: string (the post body)
- **images**: list[filepath] (optional)
- **cta_type**: string (optional — e.g., "Learn more", "Book", "Order online")
- **cta_url**: string (required if cta_type is set)

## Prerequisites

- Navigate to `https://business.google.com`
- Verify logged in: check for business dashboard elements
- If not logged in → ABORT, tell user to log in manually

## Steps

### 1. Navigate to post creation

- Find and click the "Create post" or "Add update" button
- The modal that appears is an **iframe** — do NOT try to interact with it from the parent page
- Extract the iframe's `src` URL and navigate directly to it

### 2. Add text

- Find the text area in the post form
- Enter the post body text (try `fill()` first, fall back to `execCommand` if needed)
- Verify text was entered

### 3. Add images (if provided)

- **Convert all images to JPG first** — WebP silently fails:
  ```bash
  sips -s format jpeg input.webp --out output.jpg
  ```
- Click the image/photo upload button
- Wait for `input[type="file"]` to appear
- Inject via DataTransfer API

### 4. Add CTA button (if provided)

- Click "Add link fields" button
- Click the dropdown button (defaults to "None")
- Select the desired option by matching `innerText` in the Material dropdown options
- Wait for URL input field to appear (usually the last `input[type="text"]` or `input[type="url"]`)
- Set the URL value and dispatch `input` + `change` events

### 5. Publish

- Click "Publish" / "Post" button
- Wait for confirmation or redirect

## Known Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| Can't interact with post modal | It's an iframe | Extract iframe src, navigate directly |
| Image upload silently fails | WebP format | Convert to JPG with `sips` |
| CTA URL field not found | Didn't click "Add link fields" first | Ensure the button is clicked and dropdown is set before looking for URL input |
