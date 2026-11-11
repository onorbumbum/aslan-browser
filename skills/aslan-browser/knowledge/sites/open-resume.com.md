# open-resume.com

## Resume parser (ATS proxy check)
- URL: `https://www.open-resume.com/resume-parser`. Parsing runs client-side (pdf.js); the file is not uploaded to a server.
- PDF only. Convert .docx first, e.g. Pages via osascript: `tell application "Pages" to export (open POSIX file "in.docx") to POSIX file "out.pdf" as PDF`.
- `aslan upload <pdf>` on the page's single `input[type=file]` works; results render after `aslan wait --idle`.
- To re-test another file, `aslan nav` back to the URL first (the input does not re-fire on a second upload).
- Pull just the job segmentation: `aslan eval 'return [...document.querySelectorAll("table")].map(t=>t.innerText).join("\n").split("\n").filter(l=>/^(Company|Job Title|Date)\t/.test(l)).join("\n")'`
- It is a heuristic parser (bold = company, keyword = title), not Workday. Use it to compare before/after segmentation, not as proof of Workday behavior.
