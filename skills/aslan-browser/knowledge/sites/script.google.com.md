# Google Apps Script

- In the project editor, code can be extracted from Monaco with:
  ```javascript
  return window.monaco?.editor?.getModels()?.[0]?.getValue()
  ```
- Project Settings exposes Script Properties as regular input/textbox values in the DOM. To inspect without clicking Edit:
  ```javascript
  return JSON.stringify(Array.from(document.querySelectorAll('input,textarea')).map(e => ({aria: e.getAttribute('aria-label'), value: e.value})))
  ```
- Executions and Triggers pages have useful text output via `aslan text`; trigger rows include last run, event type, function, and error rate.
