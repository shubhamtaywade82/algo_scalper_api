# Cursor Cloud Agent Prompt: Documentation Audit & Cleanup

Copy the prompt below and paste it directly into Cursor Cloud Agent. This prompt is specifically tailored to your `algo_scalper_api` repository.

---

## 📋 The Prompt

You are a senior software architect performing a documentation audit for a production trading system.

**Repository Context:** This is a Ruby on Rails-based algorithmic trading system (`algo_scalper_api`) using DhanHQ APIs, WebSocket feeds, automated order execution, and specialized strategy engines.

**The Problem:**
The repository contains a massive `docs/` directory full of historical analyses, outdated setup guides, and duplicated architecture documents that no longer match the implementation.

**Your Mandate:**
The codebase is the **single source of truth**. Documentation must reflect **actual code behavior only**. Anything not provably supported by the code must be updated, moved to `docs/archive/`, or deleted. Never invent architecture or features that do not exist in the code.

Follow this multi-phase approach strictly.

### Phase 1: Build Code Understanding (Analysis Only)
First, analyze the entire repository to understand the real architecture. Do NOT modify any documents yet.
Focus especially on:
- Trading execution flow (`app/services/live`, `app/services/orders`)
- DhanHQ API integration
- WebSocket feed listener
- Strategy engines (`app/services/strategy`, `app/services/signal`)
- Risk management & trailing (`app/services/risk`)

Produce an internal architecture map before touching any documentation.

### Phase 2: Documentation Audit
Review the `README.md` and all Markdown files inside the `docs/` directory (e.g., `COMPLETE_SYSTEM_FLOW.md`, `TRADING_SYSTEM_GUIDE.md`, etc.).

For each document:
1. Determine what feature or subsystem it describes.
2. Locate the relevant code.
3. Validate if the implementation actually exists and behaves as described.

Classify each document into one of these categories:
- **VALID**: Matches current implementation. Needs minimal updates.
- **OUTDATED**: Concept exists, but documentation does not match the current implementation.
- **IRRELEVANT**: Feature or system no longer exists.
- **UNCERTAIN**: Cannot confidently verify from the codebase.

### Phase 3: Cleanup & Restructuring Plan
Apply the following rules to the documents:
- **If VALID**: Keep and polish wording.
- **If OUTDATED**: Rewrite to exactly match the real code.
- **If IRRELEVANT**: Move to `docs/archive/`.
- **If UNCERTAIN**: Move to `docs/archive/needs-review/`.

Create a clean, standardized folder structure inside `docs/`:
- `docs/architecture/` (e.g., system-overview, execution-flow)
- `docs/trading/` (e.g., strategy-engine, risk-management, order-execution)
- `docs/integrations/` (e.g., dhanhq-api, websocket-integration)
- `docs/development/` (e.g., local-setup, testing)
- `docs/archive/` (Everything historical goes here!)

Every final functional document must:
- Reference actual files in the codebase (e.g., `app/services/orders/executor.rb`).
- Avoid speculation or future plans.
- Be short, precise, and technical.

### Phase 4: README Rewrite
Rewrite the root `README.md` to be the true entry point for new developers. It must include:
- System overview & architecture summary
- Tech stack
- Core trading flow
- Setup instructions

### Final Deliverables
Do not modify files until you have presented a plan. Your first output must be a Markdown report titled `docs_audit_report.md` detailing:
1. List of VALID docs to keep.
2. List of OUTDATED docs to rewrite.
3. List of IRRELEVANT/UNCERTAIN docs to move to `docs/archive/`.
4. The proposed new documentation structure.
5. A summary of the real architecture discovered.

Wait for my approval on `docs_audit_report.md` before applying the changes.

---

## 🛠️ Step 2: Applying the Changes
Once Cursor Agent generates the `docs_audit_report.md` and you approve of the restructuring, reply to the agent with:

> "The audit report looks good. Please proceed with Phase 3 and Phase 4. Execute the documentation cleanup, create the archive folders, move the files, rewrite the outdated docs, and generate the final README.md."

---

## 🛡️ Step 3: Enforcing Doc Standards
After the cleanup is done, create a Cursor rule file to maintain documentation sync in the future.

Create a file at `.cursor/rules/docs.mdc` with this content:

```mdc
---
description: Documentation Standards
globs: docs/**/*.md, README.md
---

# Documentation Standards

1. **Code is Truth:** Documentation must be derived from real code.
2. **No Hypotheticals:** Never document hypothetical or planned features as if they exist.
3. **Explicit References:** Documentation must reference actual implementation files.
   *Example:*
   Exit Management
   Implementation: `app/services/orders/executor.rb`
4. **Archiving:** Move outdated implementation logs and design docs to `docs/archive/`.
5. **Brevity:** Prefer short technical docs over long speculative ones.
```
