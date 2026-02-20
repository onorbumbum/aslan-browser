# Prompts Are Code

A methodology for programming LLMs with structured, deterministic workflows instead of ad-hoc conversation. This document teaches the concept deeply enough to design a Prompts-are-Code workflow for any task.

---
## 1. The Mental Model

An LLM is a general-purpose computer. It is slow, unreliable, and non-deterministic — but it is programmable. A prompt is a program. When you "chat" with an LLM, you are writing spaghetti code — no structure, no state management, no reproducibility. When you write a structured workflow prompt, you are writing a real program that executes on the LLM.

This is metaprogramming: you write "code" in natural language that executes on the LLM to produce actual work — code, documents, analysis, transformations, anything.

Everything you know about writing good software applies:

| Traditional Program | LLM Program |
|---|---|
| Source code | Workflow document (markdown) |
| Variables | Values extracted into context ("Store these for later use") |
| Functions | Pre-written tool calls (jq queries, scripts, CLI commands) |
| State / Database | JSON files on disk, queried and updated via `jq` |
| Memory / Logs | Markdown files (conventions, notes, discoveries) |
| Control flow | Sequential steps, loops ("Repeat for each"), conditionals ("If X, abort") |
| I/O | Tool calls (read files, run commands) and user input |
| Libraries | External scripts, MCP tools, CLI utilities |
| Error handling | Defensive instructions, validation gates, explicit failure paths |
| Main loop | The repeating workflow that processes work items |

The goal: **determinism, reproducibility, resumability, and context efficiency** — as much as possible within the limits of an inherently non-deterministic system.

---

## 2. Why This Works (And Why Ad-Hoc Fails)

LLMs have four fundamental weaknesses that compound in complex tasks:

**Context limits are real.** Performance degrades well before the advertised context window. Around 100k tokens, models lose track of details. Benchmarks lie. The only defense is aggressive context engineering — keeping only what's needed, when it's needed.

**LLMs lack taste.** Trained on the statistical mean of all code and text, they default to over-engineered, "best practice" solutions. Without constraints, they generate bloated output that drifts from your actual needs. Conventions files and explicit instructions are the constraints.

**LLMs can't hold complex execution flow.** They struggle with anything beyond sequential logic — concurrent processes, dependency graphs, multi-file coordination. Pre-computing the execution plan and feeding them one step at a time sidesteps this weakness.

**Context degrades over time.** As a session grows with tool outputs, file contents, and conversation history, earlier information gets buried. State on disk solves this — every session starts fresh, loads only what's needed, and picks up exactly where the last one stopped.

The Prompts-are-Code methodology doesn't fight these weaknesses. It routes around them.

---

## 3. Core Principles

### 3.1 Context Is Sacred

Every token in context competes for the LLM's attention. Irrelevant context doesn't just waste space — it actively degrades performance. Engineer context like memory in an embedded system.

**Rules:**
- Load only what the current step needs. Drop everything else.
- Pre-compute summaries instead of loading raw data when full content isn't needed.
- Read files in full when they matter — never let the LLM work with partial information on critical inputs.
- Use parallel reads for independent files to minimize turns.
- Design each loop iteration to re-load its own context fresh, not rely on what earlier iterations loaded.

### 3.2 Pre-Compute Outside the LLM

The LLM's job is reasoning and generation. Everything else — file discovery, dependency analysis, data structuring, diffing, parsing — should happen in scripts before the LLM touches it.

**Why:**
- **Determinism.** Scripts produce the same output every time. LLM exploration might miss files, use wrong patterns, or get lost.
- **Speed.** Scripts run in seconds. LLM exploration takes orders of magnitude longer.
- **Context efficiency.** Pre-computation saves hundreds of tool calls and thousands of tokens that would otherwise go to exploration.
- **Accuracy.** AST parsers, git diff, dependency analyzers are exact. LLM analysis of the same data is approximate.

This transforms open-ended exploration into structured data processing. Instead of "figure out what needs doing," the LLM gets "here's exactly what needs doing, structured and ordered."

### 3.3 Persist State to Disk

Context is ephemeral — sessions end, compaction wipes history, degradation buries information. Disk is permanent.

**Two formats:**
- **JSON** for structured data — queryable and surgically updatable via `jq`. Use for: work item tracking, configuration, progress, structured results.
- **Markdown** for unstructured knowledge — human-readable and fully loadable into context. Use for: conventions, notes, discoveries, guidelines.

**The payoff:** Any session can resume from any point. Load the state file, load the knowledge files, and continue. No lost progress. No re-explanation. No hoping the LLM "remembers."

### 3.4 Write Deterministic Workflows

Structure prompts as programs with explicit steps, not as conversations or suggestions.

- Numbered steps execute in sequence.
- "Repeat for each" creates loops.
- "If X, then Y" creates conditionals.
- "In parallel" batches independent operations.
- "STOP and wait" creates breakpoints.
- "If this fails, abort" handles errors.

The LLM follows a defined path. It doesn't improvise the path.

### 3.5 Pre-Write Your Tool Calls

Every tool invocation the workflow needs — every `jq` query, every script call, every CLI command — should be pre-written and tested. Embed them as code blocks in the workflow document.

**Why:** Without pre-written commands, the LLM will craft its own. They will be subtly wrong. It will waste turns debugging them. Pre-written, tested tool calls are deterministic and correct.

### 3.6 Program Defensively

LLMs will find every footgun you leave available. Constrain them.

- **Explicit negations:** "DO NOT use X for this step." "Do NOT change Y."
- **Failure handling:** "If this fails, abort and report the error."
- **Anti-laziness:** "Read the ENTIRE file so it is fully in your context."
- **Priority markers:** "CRITICAL:" for instructions that must not be skipped.
- **Tool restrictions:** "MUST use ripgrep instead of grep."
- **Scope limits:** "For other languages, we cannot do X and should not try to."

If you can imagine the LLM doing something wrong, it will. Prevent it in the instructions.

### 3.7 Capture Knowledge Persistently

During execution, the LLM will discover edge cases, patterns, and gotchas. Without a mechanism to capture them, they die with the session and get re-discovered (or not) in the next one.

Two persistent knowledge files:
- **Conventions file** — the rules of the domain (generated once, loaded always).
- **Notes file** — runtime discoveries (grows during execution, loaded always).

Both survive across sessions. They are the workflow's learned knowledge.

### 3.8 Minimize Turns and Waste

Every turn costs tokens and time. Optimize:
- Parallel tool calls for independent operations.
- Batch file reads.
- Surgical `jq` queries that extract exactly what's needed.
- `| head -1` to get just the next item, not all items.
- Pre-written commands that work on the first try.

---

## 4. State Design

State is the backbone of a Prompts-are-Code workflow. It defines what work exists, what's been done, and what remains. It lives on disk as JSON, survives across sessions, and drives the main loop.

### 4.1 The Plan File

The central state artifact. A JSON file that serves as both initial input and progress tracker.

**Anatomy:**

```json
{
  "metadata": {
    "description": "What this plan is for",
    "generatedAt": "2025-01-15T...",
    "config_key_1": "value",
    "config_key_2": "/absolute/path/to/something"
  },
  "workItems": [
    {
      "id": "unique-identifier",
      "status": "pending",
      "inputField1": "...",
      "inputField2": "...",
      "candidateFiles": ["/absolute/path/one", "/absolute/path/two"]
    }
  ]
}
```

**Metadata** holds configuration that applies to the entire workflow — paths, parameters, settings. Extracted once during setup, referenced throughout.

**Work items** are the ordered list of things to process. Each has:
- A unique identifier for surgical updates.
- A **status** field: `pending` → `done` (or `skipped`, `error` — whatever states the workflow needs). This is what makes the workflow resumable.
- Input fields — everything the LLM needs to know *what* to process (the workflow document defines *how*).
- Optional output fields for capturing results.

**Design rules:**
- **Pre-generate with scripts.** The LLM should never build the plan file. Scripts are deterministic and fast.
- **Flat structures.** Deeply nested JSON is hard for `jq` and hard for the LLM to reason about.
- **Absolute paths.** No ambiguity. No relative path resolution errors.
- **All IDs and status fields at the same depth.** Makes `jq` queries consistent.

### 4.2 Reading State

Pre-write every read query. These are the "getter functions" of your program.

```bash
# Load configuration (run once in setup)
jq '.metadata' plan.json

# Get next pending work item
jq -r '.workItems[] | select(.status == "pending") | .id' plan.json | head -1

# Get full details of a specific item
jq --arg id "item-1" '.workItems[] | select(.id == $id)' plan.json

# Get progress summary
jq -r '
  .workItems | length as $total |
  [.[] | select(.status == "done")] | length as $done |
  "\($done)/\($total) complete (\($done * 100 / $total | floor)%)"
' plan.json

# Count items by status
jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' plan.json
```

The `| head -1` pattern is important — it gets just the next item, preventing the LLM from loading all remaining items into context.

### 4.3 Updating State

Pre-write every write query. These are the "setter functions" of your program.

```bash
# Mark item as done
jq --arg id "item-1" \
  '(.workItems[] | select(.id == $id) | .status) = "done"' \
  plan.json > tmp.json && mv tmp.json plan.json

# Mark item as error with message
jq --arg id "item-1" --arg err "Compilation failed" \
  '(.workItems[] | select(.id == $id)) |= . + {"status": "error", "errorMsg": $err}' \
  plan.json > tmp.json && mv tmp.json plan.json
```

**The `tmp.json` pattern:** `jq` cannot edit files in place. Always redirect to a temp file and move it back. Pre-write this exact pattern — the LLM will forget the move step or try to pipe back to the same file if left to its own devices.

---

## 5. Context Engineering

Context engineering is the discipline of controlling exactly what information is in the LLM's working memory at each point in the workflow.

### 5.1 The Three Tiers

**Tier 1 — Always loaded.** Present from the start of every session:
- The workflow document itself
- Conventions file
- Notes file
- Plan metadata

These are small, essential, and needed throughout. They form the LLM's "operating system."

**Tier 2 — Loaded per work item.** Brought in fresh for each iteration of the main loop:
- Source files relevant to the current item
- Target files to be modified
- Specific data or context the current step needs

Loaded explicitly by the workflow steps. Dropped naturally as the loop iterates and context shifts.

**Tier 3 — Never loaded.** Actively excluded:
- Files irrelevant to the current task
- Raw tool outputs from previous iterations
- Completed work item details
- Large files that can be summarized instead

### 5.2 Loading Patterns

**Full reads for critical files:**
```
Read the ENTIRE file so it is fully in your context!
```
When accuracy matters, the LLM must have complete information. Partial reads lead to partial (wrong) outputs.

**Chunked reads for large files:**
```
For large files (>2000 lines): Read in chunks of 1000 lines
```
Define the chunk strategy rather than letting the LLM guess.

**Parallel reads for independent files:**
```
Read these files in parallel:
- file-a.ext
- file-b.ext
- file-c.ext
```
Reduces turns. The LLM issues multiple read calls simultaneously.

**Surgical reads via jq:**
```bash
jq '.workItems[3]' plan.json
```
Extract exactly what's needed from large JSON rather than loading the whole file.

### 5.3 Variable Assignment

LLMs don't have variables, but you can simulate them by telling the LLM what to remember:

```
Store these values for later use:
- targetRuntime (e.g., "spine-cpp")
- targetPath (e.g., "/path/to/target")
- language (e.g., "cpp")
```

This is a variable assignment instruction. The LLM will retain these values in context and substitute them when referenced later. Reinforce with string interpolation syntax:

```
Read `${targetRuntime}-conventions.md` in full.
```

The LLM resolves `${targetRuntime}` to the stored value. This is not magic — it's just natural language instruction that the LLM follows.

---

## 6. Workflow Architecture

Every Prompts-are-Code workflow has three parts: **Setup**, **Main Loop**, and **Completion**. The workflow document is a markdown file that defines all three.

### 6.1 Setup Phase (One-Time)

Runs once at the start of each session. Loads everything the workflow needs to operate.

```markdown
### 1. Setup (One-time)

1. Read configuration:
   ```bash
   jq '.metadata' plan.json
   ```
   - If this fails, abort and tell user to run the plan generator.
   - Store these values for later use:
     - projectName
     - sourcePath
     - targetPath

2. In parallel:
   a. Read `conventions.md` in full.
      - If missing: [instructions to generate it]
   b. Read `notes.md` in full.
      - If missing, create with content:
      ```markdown
      # Notes
      ```
```

**Pattern:** Read state → validate → load knowledge files → generate missing knowledge files.

The setup phase establishes the LLM's "working environment." After setup, the context contains: the workflow itself, configuration values, conventions, and notes. Nothing else.

### 6.2 Main Loop

The repeating workflow that processes work items one at a time.

```markdown
### 2. Process Items (Repeat for each)

1. **Find next pending item:**
   ```bash
   jq -r '.workItems[] | select(.status == "pending") | .id' plan.json | head -1
   ```
   - If no pending items remain, go to Completion.

2. **Load context for this item:**
   - Read source files relevant to this item
   - Read target files if they exist
   - Read any dependencies

3. **Analyze:**
   - [domain-specific analysis steps]
   - [decision framework for handling what's found]

4. **Execute:**
   - [domain-specific transformation/generation steps]
   - [verification after each significant change]

5. **Verify:**
   - [checklist of what "done" means]

6. **Update state:**
   ```bash
   jq --arg id "ITEM_ID" \
     '(.workItems[] | select(.id == $id) | .status) = "done"' \
     plan.json > tmp.json && mv tmp.json plan.json
   ```

7. **Update notes:**
   - Add any new patterns or edge cases discovered.
```

**Key patterns in the main loop:**

- **Step 1** queries for the next item. The `| head -1` ensures only one item enters context. When nothing is pending, the loop terminates.
- **Step 2** loads fresh context per item. Previous iteration's files are no longer needed.
- **Step 3** is where domain-specific reasoning happens, guided by decision frameworks (see 6.4).
- **Step 6** writes state to disk immediately after completion — the resumability guarantee.
- **Step 7** captures discoveries — the knowledge accumulation guarantee.

### 6.3 Completion Phase

Runs once when all work items are processed.

```markdown
### 3. Completion

1. Show final progress:
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' plan.json
   ```
2. Summarize what was done.
3. List any items with errors or skipped status for user review.
```

### 6.4 Decision Frameworks

When the workflow involves judgment — not just mechanical transformation — provide explicit decision criteria. This constrains the LLM to defined categories instead of ad-hoc reasoning.

```markdown
Decision framework for each difference found:
- Is this an idiomatic difference between source and target?
  → Keep target's approach, ensure same functionality
- Is this old functionality that source removed?
  → Remove from target
- Is this new functionality that source added?
  → Add to target following conventions
- Is this a behavioral difference?
  → Update target to match source behavior exactly
```

Without a decision framework, the LLM will make inconsistent choices across work items. With one, every decision follows the same logic.

### 6.5 Verification Checklists

Define what "done" means for each work item. The LLM checks these before marking status as done.

```markdown
Verification checklist:
- All expected outputs exist
- No unintended changes to adjacent code/content
- Conventions file was followed
- Output matches the specification exactly
- [domain-specific checks: compilation, tests, parity, etc.]
```

Without a checklist, "done" is whatever the LLM feels like. With one, "done" is verifiable.

---

## 7. The Function Library

A section in the workflow document that defines every tool invocation as a labeled, tested code block. This is the "import" section of your program.

### 7.1 Categories

**State queries** — reading from the plan file:
```bash
# Get next pending item
jq -r '...' plan.json | head -1
```

**State mutations** — writing to the plan file:
```bash
# Mark item done
jq --arg id "$ID" '...' plan.json > tmp.json && mv tmp.json plan.json
```

**Progress tracking** — summarizing overall status:
```bash
# Show completion percentage
jq -r '...' plan.json
```

**Analysis tools** — scripts that examine inputs:
```bash
# Analyze differences between source and target
./analyze.js <item-id>
```

**Validation tools** — verifying outputs:
```bash
# Compile/lint/test the output
./validate.js <file-path>
```

**Display tools** — showing work to the user:
```bash
# Open files in editor, show diffs, display results
```

### 7.2 Writing Good Function Definitions

Each function block should be:
- **Labeled** with a comment explaining what it does
- **Complete** — copy-paste runnable, no missing flags or arguments
- **Tested** — you (or a script) verified it works before embedding it
- **Parameterized** with clear placeholders that the LLM can substitute

Bad:
```bash
jq '.workItems | map(select(.status == "pending"))' plan.json
```

Good:
```bash
# Get next pending work item's full details
jq -r '.workItems[] | select(.status == "pending")' plan.json | head -1
```

The label tells the LLM *when* to use it. The `head -1` prevents loading all pending items. The `-r` flag gives raw output.

---

## 8. Defensive Programming

LLMs are unreliable executors. Defensive programming is not optional — it is the difference between a workflow that completes reliably and one that derails at step 3.

### 8.1 Explicit Negations

Tell the LLM what NOT to do. This is as important as telling it what to do.

```
DO NOT use the TodoWrite and TodoRead tools for this phase.
DO NOT attempt to compile individual files for this language.
DO NOT modify files outside the target directory.
DO NOT skip the verification checklist.
```

**Why this works:** LLMs have strong priors from training. They will reach for familiar tools and patterns even when inappropriate. Explicit negations override those priors.

### 8.2 Failure Handling

Every step that can fail needs a failure path.

```
1. Read configuration:
   ```bash
   jq '.metadata' plan.json
   ```
   - If this fails, abort and tell user to run generate-plan.js first.
```

```
5. Validate output:
   ```bash
   ./validate.js output-file
   ```
   - If validation fails, report the errors and ask user how to proceed.
   - Do NOT attempt to auto-fix validation failures without explicit instructions.
```

### 8.3 Anti-Laziness Instructions

LLMs will take shortcuts — reading partial files, skipping steps, summarizing instead of doing the work. Prevent it:

```
Read the ENTIRE file so it is fully in your context!
Port EVERY method, not just the ones that changed.
Check ALL items in the verification list, not just the first few.
```

### 8.4 CRITICAL Markers

For instructions that absolutely must not be skipped:

```
CRITICAL: The output must match the specification exactly. Do not approximate.
CRITICAL: Update the state file BEFORE proceeding to the next item.
```

Use sparingly. If everything is CRITICAL, nothing is.

### 8.5 Tool Preference

When multiple tools could accomplish a task, specify which one:

```
Agents MUST use ripgrep instead of grep.
Use jq for all JSON operations — do NOT parse JSON manually.
Use MultiEdit for all changes to one file.
```

### 8.6 Scope Boundaries

Prevent the LLM from expanding scope:

```
Only modify files within the target directory.
Only process items listed in the plan file.
If you encounter an issue outside the current work item's scope, add it to notes.md and continue.
```

---

## 9. Knowledge Persistence

### 9.1 The Conventions File

A markdown file documenting the rules, patterns, and style of the domain the workflow operates in.

**When to create it:** During the Setup phase, if it doesn't already exist. The workflow should include instructions for generating it — either by analyzing existing files or by asking the user.

**What it contains (adapt to domain):**
- Naming conventions (casing, prefixes, suffixes)
- File organization patterns
- Structural patterns (how things are defined, organized, related)
- Style preferences
- Domain-specific rules and constraints
- What to avoid

**Example generation instruction in a workflow:**
```
If conventions.md is missing:
  - Use sub-agents in parallel to analyze the target directory
  - Document all patterns found:
    * Naming conventions
    * File organization
    * Structural patterns
    * Style patterns
  - Sub-agents MUST use ripgrep instead of grep
  - Save as conventions.md
  - STOP and ask user to review
```

**Why generate-then-review:** The LLM does the tedious analysis. The human verifies it's correct. The result is a reliable reference that prevents the LLM from inventing its own conventions.

### 9.2 The Notes File

A running markdown log of discoveries made during workflow execution.

**Created:** Empty at the start (just a `# Notes` header).

**Updated:** After every work item that reveals something new — an edge case, a pattern, a gotcha, a decision that should apply to future items.

**Loaded:** Into context at the start of every session.

**Example entries:**
```markdown
# Notes

## Date Formatting
- Source uses ISO 8601 everywhere but the API expects Unix timestamps
- Conversion must happen at the boundary, not inside business logic

## Error Handling Edge Case
- The `processPayment` function can return null on timeout, not just on failure
- All callers must handle the null case separately from the error case

## Convention Override
- Module X uses snake_case despite the project convention of camelCase
- This is intentional per the team — do not "fix" it
```

The notes file is the workflow's institutional memory. Without it, every session rediscovers the same issues.

---

## 10. The Design Process

How to go from "I have a task" to "I have a complete Prompts-are-Code workflow." This is the meta-process — the procedure for creating a workflow program.

### Step 1: Decompose the Task

Answer these questions:

- **What is the input?** A codebase, a dataset, documents, API responses, a specification — what raw material does the workflow operate on?
- **What is the desired output?** Code changes, generated files, reports, transformed data — what does "done" look like?
- **What are the discrete work items?** Files to process, features to implement, records to transform, sections to write — what are the individual units of work?
- **Is the work repetitive?** If the same operation applies to many items, you have a main loop. If not, you have a sequential pipeline.
- **What ordering matters?** Are there dependencies between work items? Can they be processed in any order, or must some complete before others?
- **What knowledge is needed?** Conventions, domain rules, style guides, architectural context — what must the LLM know to do the work correctly?
- **What can go wrong?** Failure modes, edge cases, common mistakes — what defensive measures are needed?

### Step 2: Identify Pre-Computation Opportunities

For each part of the task, ask: **Can a script do this instead of the LLM?**

- File discovery → `find`, `rg`, `git diff`, `ls`
- Dependency analysis → AST parsers, import analyzers, custom scripts
- Data structuring → Scripts that output JSON
- Diffing → `git diff`, `diff`, custom diff tools
- Ordering → Topological sort scripts, dependency resolvers
- Validation → Compilers, linters, test runners

Build (or specify) the scripts that generate the plan file. The plan file is the bridge between pre-computation and LLM execution.

### Step 3: Design the State Schema

Based on Step 1 and Step 2, design the plan.json structure:

1. **Metadata section:** All configuration the workflow needs — paths, parameters, settings.
2. **Work items array:** One entry per discrete work item from Step 1.
3. **Per-item fields:**
   - Unique identifier
   - Status field (`pending`/`done`/`skipped`/`error`)
   - All input data the LLM needs for this item
   - Candidate outputs or target locations
4. **Write every jq query** the workflow will use — reads, writes, progress tracking. Test them against sample data.

### Step 4: Map the Context Strategy

For each phase of the workflow, define exactly what's in context:

- **Setup:** Workflow + metadata + conventions + notes. Nothing else.
- **Per work item:** Add only the files/data needed for that item. List them explicitly.
- **Excluded:** List what should never be loaded. Be specific.

If any input is large (>2000 lines), define a chunking strategy. If multiple files are independent, mark them for parallel loading.

### Step 5: Write the Workflow Document

Assemble the workflow as a markdown file with these sections:

```markdown
# [Workflow Name]

[Brief description. What this workflow does and what state it tracks.]

[State schema with annotated JSON example]

## Tools

[Every tool invocation as a labeled, tested code block]

## Workflow

### 1. Setup (One-time)
[Load config, conventions, notes. Validate prerequisites.]

### 2. Main Loop (Repeat for each)
[Query → Load → Analyze → Execute → Verify → Update state → Update notes]

### 3. Completion
[Final summary, error review]
```

For each step in the main loop:
- Write the exact tool calls.
- Write decision frameworks for judgment calls.
- Write verification checklists for quality gates.
- Write defensive instructions for known failure modes.

### Step 6: Write the Knowledge Files

**Conventions file:** Either write it manually, or include instructions in the Setup phase for the LLM to generate it by analyzing the domain, then stop for human review.

**Notes file:** Create an empty one with just a header. It will grow during execution.

### Step 7: Harden the Workflow

Review the complete workflow document and ask:

- For every step: **What could the LLM do wrong here?** Add a defensive instruction.
- For every tool call: **Is this tested and complete?** No missing flags, no ambiguous placeholders.
- For every judgment call: **Is there a decision framework?** If not, the LLM will be inconsistent.
- For every output: **Is there a verification check?** If not, "done" is undefined.
- For every instruction: **Could this be misinterpreted?** If so, clarify.
- Globally: **Are there tools or approaches the LLM should NOT use?** Add explicit negations.

---

## 11. Patterns Reference

Reusable patterns extracted from real Prompts-are-Code workflows.

### 11.1 The Delta Analysis Pattern

When the task involves comparing a source to a target and reconciling differences:

```markdown
Analysis approach:
1. Understand what the source currently has
2. Understand what the target currently has
3. Identify the delta:
   - What's in source but missing from target → ADD
   - What's in target but not in source → REMOVE (unless idiomatic)
   - What exists in both but differs → UPDATE to match source
   - What's identical → LEAVE ALONE
```

Applicable to: porting, migrations, synchronization, reconciliation tasks.

### 11.2 The Convention Generation Pattern

When the workflow needs to respect existing patterns it hasn't been told about:

```markdown
If conventions.md is missing:
  - Use sub-agents in parallel to analyze [target directory]
  - Document all patterns:
    * [List of specific things to look for]
  - MUST use ripgrep instead of grep
  - Save as conventions.md
  - STOP and ask user to review
```

Applicable to: any workflow that modifies an existing codebase or content body.

### 11.3 The Incremental Checkpoint Pattern

When work items are large and you want partial progress safety:

```markdown
Port incrementally:
1. Structure first (signatures, declarations)
2. [Run validation]
3. Implementation (method bodies, logic)
4. [Run validation]
5. Polish (documentation, formatting)
6. [Run validation]
```

Applicable to: any workflow where individual work items are large enough to fail partway through.

### 11.4 The Skip-Detection Pattern

When some work items may not need processing:

```markdown
4. Analyze changes:
   ```bash
   ./analyze-diff.js <item-id>
   ```
   - If no changes detected:
     - Tell user: "No changes needed for <item>. Mark as done? (y/n)"
     - If yes, skip to state update step
```

Applicable to: any workflow where pre-computation can't perfectly predict which items need work.

### 11.5 The Dependency Chain Pattern

When processing an item requires understanding its dependencies:

```markdown
4. Read dependencies:
   - Check the item's declaration for references to other items
   - For each dependency, read its source in full
   - Continue recursively until the full dependency chain is in context
```

Applicable to: code generation, porting, any task with type/module dependencies.

### 11.6 The Parallel Sub-Agent Pattern

When analysis work can be split across independent agents:

```markdown
Use sub-agents in parallel to:
  a. Analyze directory A for pattern X
  b. Analyze directory B for pattern Y
  c. Analyze directory C for pattern Z
Combine results into a single output file.
```

Applicable to: large-scale analysis, convention discovery, multi-module tasks.

---

## 12. Anti-Patterns

What NOT to do when designing Prompts-are-Code workflows.

### 12.1 Letting the LLM Explore

**Wrong:** "Look through the codebase and figure out what needs changing."
**Right:** Pre-compute the list of what needs changing and hand it to the LLM as structured JSON.

### 12.2 Trusting Context to Persist

**Wrong:** Assuming information from turn 5 is still accurately attended to at turn 50.
**Right:** Write state to disk. Re-load what's needed. Design for session boundaries.

### 12.3 Vague Instructions

**Wrong:** "Make sure the output is good."
**Right:** "Verify: all method signatures match, all constants are identical, documentation is updated."

### 12.4 Overloading a Single Step

**Wrong:** "Read all files, analyze them, transform them, and validate the results."
**Right:** Separate steps: read, analyze, transform, validate. Each step has clear inputs and outputs.

### 12.5 No State Updates After Work

**Wrong:** Processing multiple items, then updating state at the end.
**Right:** Update state immediately after each item. If the session dies mid-run, progress is preserved.

### 12.6 Generating the Plan with the LLM

**Wrong:** Having the LLM analyze the codebase to build the plan file.
**Right:** A script builds the plan. The LLM executes against it. The only exception: generating conventions files, which require the LLM's pattern recognition but should be human-reviewed.

### 12.7 Implicit Decision Making

**Wrong:** Letting the LLM decide how to handle edge cases with no guidance.
**Right:** Decision frameworks that categorize cases and define the action for each category.

---

## 13. Summary

The Prompts-are-Code methodology is built on one insight: **treat LLMs as programmable computers, not conversation partners.** From this, everything follows:

- **Pre-compute** what scripts can handle. Feed the LLM structured data.
- **Persist state** to JSON on disk. Query and update it surgically with `jq`.
- **Engineer context** ruthlessly. Load only what's needed, when it's needed.
- **Write deterministic workflows** with explicit steps, loops, conditionals, and error handling.
- **Pre-write tool calls** so the LLM executes tested commands, not improvised ones.
- **Program defensively** with explicit negations, failure paths, and anti-laziness instructions.
- **Capture knowledge** in conventions and notes files that survive across sessions.
- **Design for resumability.** Any session can pick up where the last one stopped.

The result: reproducible, resumable, context-efficient workflows that turn unreliable LLMs into reliable executors of structured work.
