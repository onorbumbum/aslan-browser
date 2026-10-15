# Gmail Web

## Recovering Gmail API message IDs from an open thread

When the user provides a Gmail web URL token, Toolshed correctly rejects it as an API message/thread ID. Open the thread in Gmail and inspect expanded message containers:

```bash
ASLAN_SESSION=<session> aslan eval 'return [...document.querySelectorAll("[data-legacy-message-id]")].map(e=>({id:e.getAttribute("data-legacy-message-id"),text:e.innerText.slice(0,500)}))'
```

- `data-legacy-message-id` is the hexadecimal Gmail API message ID accepted by `toolshed gmail ... message get` and `reply --message`.
- Use the accompanying message text to select the intended message, especially when a thread contains several replies.
- Read the selected message through Toolshed before replying so To/Cc/Bcc roles are confirmed from normalized headers.
