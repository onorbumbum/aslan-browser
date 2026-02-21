# reddit.com

## Post Creation (New Reddit / shreddit)

### Title Field
- Not a regular input. It's a `<faceplate-textarea-input>` web component.
- The actual `<textarea>` is inside its **shadowRoot**: `document.querySelector("faceplate-textarea-input").shadowRoot.querySelector("textarea")`
- Set `.value` + dispatch `input` and `change` events (both with `{bubbles: true}`).

### Markdown Mode
- Default editor is rich text (contenteditable). Switch to markdown for easier text entry.
- The toggle button is inside `shreddit-composer` shadowRoot: `document.querySelector("shreddit-composer").shadowRoot.querySelector("button")` — text is "Switch to Markdown".
- In markdown mode, the body textarea is at **shadow DOM depth 2**: `faceplate-textarea-input > shadowRoot > textarea[placeholder="Body text (optional)"]`.
- Use the `deepSearch` pattern to find it — iterate `querySelectorAll("*")`, check `.shadowRoot` recursively.
- Set `.value` + dispatch `input` and `change` events.

### Flair Selection
- "Add flair and tags" button is inside `r-post-flairs-modal` shadowRoot.
- To open flair modal: find the button inside `r-post-flairs-modal` shadowRoot that contains "Add flair and tags", click it.
- Default view shows only 3-4 flairs. Must click "View all flairs" (a `<span>` inside the modal shadowRoot) to see full list.
- Select flair by finding the `faceplate-radio-input` whose textContent matches the desired flair, then `.click()` it.
- The "Add" button at modal bottom is `type=submit` but has no form reference. Regular `.click()` doesn't work. Must dispatch full pointer event sequence: `pointerdown → mousedown → pointerup → mouseup → click` (all with `{bubbles: true, cancelable: true}`).

### Post Submission
- Post button is inside `r-post-form-submit-button` shadowRoot: find button with text "Post" and click it.
- After posting, Reddit shows a "Crosspost" popup modal. Dismiss or ignore.

### Available Flairs (r/ClaudeCode)
Question, Help Needed, Bug Report, Solved, Showcase, Tutorial / Guide, Resource, Discussion, Humor

## General Reddit Shadow DOM Pattern
- Reddit's new UI (shreddit) uses web components heavily. Almost every interactive element is behind 1-3 layers of shadowRoot.
- The accessibility tree often misses elements inside shadow DOM.
- Pattern for finding deeply nested elements:
```javascript
function deepFind(root, selector, depth=0) {
  if (depth > 5) return null;
  const el = root.querySelector(selector);
  if (el) return el;
  for (const child of root.querySelectorAll("*")) {
    if (child.shadowRoot) {
      const found = deepFind(child.shadowRoot, selector, depth+1);
      if (found) return found;
    }
  }
  return null;
}
```

## Login
- Reddit keeps persistent login state in WKWebView. No need to log in each session.
- User profile visible via "Expand user menu" button in top nav.
