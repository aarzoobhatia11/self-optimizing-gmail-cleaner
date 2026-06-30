# CLAUDE.md

## What this repo is
A **Gmail cleanup tool built as Claude routines** (no local app). On a schedule, one routine scans
the inbox, labels what to delete, you review/untick in the Gmail app, and it trashes the rest and
learns your preferences. State lives in **Supabase**; the repo is public and code-only.

## Read this first
👉 **[README.md](README.md)** is the full doc — architecture, setup, how-it-works, testing. The
routine instructions live in `routines/` (`cleanup_gmail.md`, `refine_cleanup_prompt.md`), the
classifier in `prompts/classify_prompt.md`, and the DB schema in `schema.sql`. (The detailed design
doc `PLAN.md` was removed once the build was complete; the Key facts below + README cover everything.)

## Key facts (so you don't re-derive them)
- **Two routines:** `cleanup_gmail` (Routine 1 — ONE routine, 3 phases: classify · remind · delete +
  learn) and `refine_cleanup_prompt` (Routine 2 — monthly GitHub PR that improves the prompt).
- **Self-pacing:** the cleanup routine reads timestamps from `cleaner_state` and runs only the phase(s)
  that are due, so it's robust at ANY trigger frequency (weekly recommended). A run may finalize the
  matured batch AND open a new cycle, but never trashes mail it proposed in the same run.
- **Approval = ONE Gmail label `To Delete`**, reviewed in the Gmail app; auto-trashes after a
  `DELETE_AFTER_DAYS` (=3) review window. The old `Cleaner/Proposed` label is gone — the "what was
  proposed" snapshot now lives in Supabase (`cleaner_proposed`). No web UI.
- **State = Supabase** (tables in `schema.sql`: `cleaner_state/proposed/rules/examples/trust/deferred`),
  read/written via the Supabase connector — NOT in the repo, so the repo is safe to be public.
- **Env vars:** `CYCLE_DAYS=7`, `DELETE_AFTER_DAYS=3`, `REMIND_EVERY_HOURS=24`, `CHUNK_SIZE=100`,
  `LOOKBACK_DAYS=30`, `GRADUATE_ROUNDS=2`. No `MAX_EMAILS` cap — classify is chunked by `CHUNK_SIZE`.
- **Fetch = all categories, Spam + Trash excluded** (`after:<date> -in:trash -in:spam`).
- **LLM input = metadata only** (from, subject, ≤300-char snippet, size, flags) — never email bodies.
- **Classification = rules + judgment** (`prompts/classify_prompt.md`): NEVER-DELETE / ALWAYS-KEEP /
  ALWAYS-DELETE / "you decide"; `category` is a descriptive tag, not a rigid gate.
- **Few-shot examples capped at ~5**, chosen corrections-first (research-backed; more biases the model).
- The old local CLI (`cleaner.js`, `db.js`, `report-html.js`, `scheduler.js`) has been **removed**.

## Conventions
- Trash only — never permanent delete (30-day recovery).
- The prompt lives in `prompts/classify_prompt.md`, refined via a monthly GitHub PR (human-reviewed), not hand-edited.
- Files in `routines/` are the copy-paste source for each routine's "Instructions" box.
