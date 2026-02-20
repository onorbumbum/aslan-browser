# Google Business Profile — Site Knowledge

## Post Creation

- The "Create post" modal is an embedded iframe
- Cannot interact with it from the parent page — extract the iframe `src` and navigate directly to it
- Image uploads require JPG or PNG — WebP silently fails
  - Convert with: `sips -s format jpeg input.webp --out output.jpg`

## Call to Action Buttons

To add a CTA button (e.g., "Learn more"):

1. Click "Add link fields" button
2. Click the dropdown (defaults to "None")
3. Select desired option by matching `innerText` in the Material dropdown
4. A URL input field appears — find the last `input[type="text"]` or `input[type="url"]`
5. Set value and dispatch `input` + `change` events
