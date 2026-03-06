# Best-in-Class Iteration Protocol

**Purpose:** Bring this repo to best-in-class quality by iterating until all criteria pass. Use this doc when asking an AI (e.g. OpenCode, Cursor Agent) to **keep testing and improving until the system meets the bar—do not stop after one pass.**

---

## 1. How to Frame for OpenCode / Cursor (Copy-Paste)

**Goal:** The AI should **keep testing and improving until the system is best-in-class**, without stopping after one fix.

**Option A — Paste this into the agent (OpenCode, Cursor, etc.):**

```
Follow the Best-in-Class Iteration Protocol in docs/BEST_IN_CLASS_ITERATION.md.

Do not stop after one round. In each round:
1. Run the full verification suite (section 4).
2. If anything fails, fix the failures and go back to step 1.
3. If everything passes, run the full suite one more time to confirm, then stop.

Continue iterating until the exit criteria in section 3 are met. Only then report "Best-in-class iteration complete."
```

**Option B — In Cursor:** Reference the rule: `@.cursor/rules/best-in-class-iteration.mdc` and say: "Run the best-in-class iteration until done."

**Option C — Short:** "Iterate until best-in-class per docs/BEST_IN_CLASS_ITERATION.md; do not stop until all verifications pass twice in a row."

---

## 2. Definition of Best-in-Class (Exit Criteria)

The system is **best-in-class** when **all** of the following are true:

| #   | Criterion          | How to verify                                                                                     |
| --- | ------------------ | ------------------------------------------------------------------------------------------------- |
| 1   | **Code style**     | `bin/rubocop` exits 0 (no offenses).                                                              |
| 2   | **Security**       | `bin/brakeman --no-pager` reports no high/medium confidence issues (or only accepted).            |
| 3   | **Tests**          | `bin/rails test` (or `bundle exec rspec`) exits 0; no pending/skipped unless documented.          |
| 4   | **Conventions**    | Code follows CURSOR_RULES.md and CODING_CONVENTIONS.md (Rails, services, models, RSpec).          |
| 5   | **Trading safety** | No unhandled exceptions in trading path; errors logged with class context; idempotent order flow. |
| 6   | **Observability**  | Critical operations log with `[ClassName]` prefix; health/status endpoints reflect real state.    |

**Exit condition:** Run the verification suite (section 3). If every command exits 0 and the codebase meets criteria 4–6 on review, run the suite **once more** to confirm. After two consecutive full passes, stop and report completion.

---

## 3. Verification Commands (Run Every Round)

Run these in project root. Fix any non-zero exit or new failures before considering the round done.

```bash
# 1. Code style (must be clean)
bin/rubocop

# 2. Security (no high/medium unaccepted)
bin/brakeman --no-pager

# 3. Test suite (must be green)
bin/rails test
# Or if using RSpec directly:
# bundle exec rspec
```

Optional (recommended for a full pass):

```bash
# DB and app sanity
bin/rails db:test:prepare
bin/rails runner "puts 'OK'"
```

---

## 4. Iteration Loop (What the AI Should Do)

1. **Run** all commands in section 3 (Verification Commands).
2. **If any command fails:**
   - Fix the underlying issues (style, security, or tests).
   - Do not explain and stop—go to step 1.
3. **If all commands pass:**
   - Run the full verification suite **again** (section 3).
   - If the second run also passes → **exit** and report: "Best-in-class iteration complete."
   - If the second run fails → fix and go to step 1.

**Rule:** Do not stop after a single successful run. Two consecutive full passes are required.

---

## 5. Scope and Conventions

- **In scope:** All Ruby/Rails/RSpec code under `app/`, `lib/`, `spec/`, `config/` (excluding vendored assets). Follow `.cursorrules` and CURSOR_RULES.md.
- **Skills:** Use `.cursor/skills/ruby/` (Ruby style, Rails, RSpec, SOLID) when editing or reviewing code.
- **Trading code:** Prefer safety and clarity: validate inputs, handle external API failures, log with `[ClassName]`, no unhandled raises in the trading loop.

---

## 6. Quick Reference for Humans

- **“Make it best-in-class”** → Point the AI at this doc and use the prompt in section 1.
- **“Keep going until it’s done”** → Same: section 1 + section 4.
- **Manual check** → Run section 3 (Verification Commands); all green = one passing round; run again to confirm.
