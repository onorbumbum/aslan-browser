# Verify an unpublished Google Forms draft

## Prerequisites

Use an authenticated installed Aslan Browser. Have task-specific authority for draft edits. Publication, sharing, test submissions and sending are separate actions.

## Steps

1. Open https://docs.google.com/forms/u/0/ in a dedicated tab. Check Recent forms for an existing matching draft before creating another.
2. Open the draft and inspect title, description, question labels, options and types. Pin every command to the tab ID. For rich-text replacements, typing inserts at the caret rather than replacing existing text. Focus the observed contenteditable, select its contents with a Range, then use execCommand("insertText", false, replacement). Blur and verify after reload. Refresh tree refs after each mutation before another ref-based edit.
3. Read Required checkbox `aria-checked` values in question order. Hidden question editor controls exist in DOM even when their card is inactive.
4. Activate a question to inspect its type or validation. More options has a Response validation menuitemcheckbox. Add validation only when the task approves it.
5. For an email short-answer field, choose Text then Email in the validation controls. Google Forms menus may need a bubbling mousedown, mouseup, click sequence. Some `aslan click` calls return ok without changing the menu. Read after each action and allow the rerender before reusing refs.
6. Hidden templates contain duplicate listboxes and option text. Filter by a nonzero bounding rectangle and inspect `aria-selected`; never infer active validation from every listbox in the document.
7. In Settings, check quiz status, email collection, sign-in requirement, public results summary and confirmation text. An ordinary performer signup should not grade responses. Match the approved draft rather than inheriting a copied form's settings silently.
8. Reload, then independently recheck persisted content and settings.
9. Responses explicitly says `No responses. Publish your form to start accepting responses.` for a new unpublished draft. Record this as publication-state evidence, not merely the presence of a Publish button.
10. `Link to Sheets` is not proof of an existing response spreadsheet. Do not claim a response destination without checking its actual linkage.

## Publication checks when separately approved

- The Publish dialog may default responders to Specific people. Manage responders opens a same-origin `iframe[title=Content]` sharing dialog. Its General access has separate Editor view and Responder view controls. Change only Responder view to Anyone with the link when approved; keep Editor view Restricted. Wait for Access updated and Done before returning to Publish.
- In the sharing iframe, a plain `.click()` may not open a menu. Dispatch pointerdown, pointerup and click using the iframe's own window and `view` property. Read the resulting options before selecting.
- After publication, get the actual `/d/e/.../viewform` URL from Copy responder link. Recheck the response count after a separately approved synthetic submission, label the test clearly, and never delete it without authority.

## Limits

Do not publish or submit to prove the draft exists. Editor verification does not establish signed-out responder access or submission behavior. Leave old forms and responses untouched unless specifically authorized.
