# Aslan Browser — Workflow System

This directory contains Prompts-are-Code workflow documents that guide LLM agents through building aslan-browser phase by phase.

## How It Works

Each phase is a self-contained workflow document with a corresponding state file (`state/phase-N-plan.json`). An LLM agent loads the workflow document, follows the steps, and tracks progress in the state file. Work can be interrupted and resumed at any point — the state file preserves progress.

## Shared Files

| File | Purpose | When Loaded |
|---|---|---|
| `conventions.md` | Project rules, patterns, architecture decisions | Every session, always |
| `notes.md` | Runtime discoveries, edge cases, gotchas | Every session, always |

## Phases (Execute In Order)

| Phase | File | State | Description |
|---|---|---|---|
| 1 | `phase-1-skeleton.md` | `state/phase-1-plan.json` | AppKit lifecycle, BrowserTab, navigate, evaluate, screenshot |
| 2 | `phase-2-socket-server.md` | `state/phase-2-plan.json` | SwiftNIO Unix socket, JSON-RPC protocol |
| 3 | `phase-3-script-bridge.md` | `state/phase-3-plan.json` | Injected JS bridge, readiness detection |
| 4 | `phase-4-accessibility-tree.md` | `state/phase-4-plan.json` | DOM walker, a11y tree extraction, ref-based interaction |
| 5 | `phase-5-tab-management.md` | `state/phase-5-plan.json` | Multi-tab, events, cookies, navigation history |
| 6 | `phase-6-python-sdk.md` | `state/phase-6-plan.json` | Python client library, benchmarks, documentation |
| 7 | `phase-7-usability-and-multi-agent.md` | `state/phase-7-plan.json` | Edit menu (Cmd+V), window controls, address bar, sessions, batch ops |

## Rules for Agents

1. **Always load `conventions.md` and `notes.md` at session start.** These are your operating context.
2. **Work on ONE phase at a time.** Complete all work items before moving to the next phase.
3. **Update `notes.md`** whenever you discover something — edge cases, patterns, gotchas. Future sessions depend on this.
4. **Update state immediately** after completing each work item. Never batch state updates.
5. **Do NOT skip verification steps.** Compile gate must pass before marking done.
6. **Do NOT modify files outside the current work item's scope.** If you spot something, add it to notes.md.
