# Instagram — Site Knowledge

## Search

- Search input is React-based — `fill()` just sets `.value` without triggering React state updates
- Suggestion dropdown won't populate unless React detects the input
- Must use `execCommand("insertText")` via evaluate:
  ```js
  var input = document.querySelector('input[type="text"]');
  input.focus();
  input.value = '';
  document.execCommand("insertText", false, "search query");
  ```
- Wait 2-3 seconds after typing for suggestion dropdown to appear
