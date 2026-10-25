# docs/archive/

Historical planning documents, completed implementation summaries, and
superseded design notes. Material here is kept for reference and is **not**
actively maintained — links may be broken, code snippets may be stale, and
file names may duplicate live docs (the live version under `docs/<top>/`
is canonical when both exist).

## When to add to archive

- A planning doc whose work is fully shipped
- A design doc superseded by a newer version
- An investigation whose findings have been folded into the live docs

## When NOT to add to archive

- TODO lists (delete when done — they have no reference value)
- Half-finished thoughts (delete or finish — don't archive)
- Duplicates of live docs (delete the duplicate, don't archive)

## Why we keep this directory in git

Despite repo bloat (this directory is ~7MB / 294 .md files as of 2026-10),
the material is occasionally useful for understanding *why* the codebase
looks the way it does. A future cleanup could move this to a separate
`docs-archive` branch or LFS pointer; for now, the cost is acceptable.

## Maintenance

If you're touching this directory, please:
1. Don't add new entries without a good reason (see "When to add" above)
2. If you find a clear duplicate of a live doc, delete the archive copy
3. If you find a clearly stale entry (e.g. references deleted code paths),
   delete it — don't leave misleading material around
