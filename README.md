# self-optimizing-gmail-cleaner

A Gmail cleanup that runs as a Claude routine and optimizes its own classifier prompt from your keep/delete feedback.

Clean your inbox on autopilot. It labels what you'd delete, you glance and untick anything to keep, and it trashes the rest a couple of days later - learning your taste so you review less every week.

## What it does

- Scans your Gmail on a schedule and labels likely-junk under a single **`To Delete`** label
- Your whole review: **untick anything to keep**, or add the label to anything you want gone
- Trashes what's left a couple of days later - recoverable from **Trash for 30 days**
- Parks time-sensitive keeps (bookings, tickets, offers) and resurfaces them for deletion only once they **expire**
- **Learns your taste** from every keep/untick, so it needs less of your review each week
- Runs entirely in **Claude's cloud** - no server, no API credits, and it never sees your email body

## How it self-optimizes

Four feedback loops, all driven by the keep/delete edits you make each cycle:

1. **Every decision becomes an example.** Each keep/untick is saved to Supabase. On the next run it ranks your recent decisions **corrections first → confident-but-wrong → most recent**, picks the **top 5** (varied across keep/delete and categories), and injects them into the classifier as few-shot examples. The cap is small on purpose - more examples bias the model.
2. **Repeat offenders graduate to auto-delete.** Confirm-deleting a rarely-read sender a few cycles in a row promotes it to "always delete" - it stops needing your review.
3. **Time-sensitive keeps wait in a deferred queue.** A booking or ticket you keep is parked with an expiry date and resurfaced for deletion only once it's stale.
4. **A monthly PR sharpens the prompt.** The `refine` routine spots patterns in your corrections and opens a GitHub Pull Request improving the classifier's wording - you review and merge.

**Net effect:** recurring mail handles itself, and the pile that needs your eyes shrinks toward just genuinely-new senders. The approval gate never disappears - it's your safety net - you just stop needing it.

## Accounts and connectors

| Tool / account | What it's for |
|---|---|
| **Claude (Pro or Max)** | Runs the routines in Claude's cloud - no server, no API credits |
| **Claude app** | Create & watch routines and get review notifications - web, desktop, or CLI |
| **Gmail + connector** | Reads mail metadata, manages the `To Delete` label, moves mail to Trash |
| **Supabase + connector** | Your private memory database (rules, examples, trust, deferred queue) |
| **GitHub** | Hosts your fork; the `refine` routine opens prompt-improvement PRs against it |

## Setup (~10 minutes)

### 1. Fork this repo
Fork it to your own GitHub so you can attach it to a routine (and let `refine` open PRs). Safe to keep public - no personal data lives here.

### 2. Create your memory database
In [Supabase](https://supabase.com), create a free project → open the **SQL Editor** → paste and run [`schema.sql`](schema.sql). This creates the `cleaner_*` tables.

### 3. Connect Gmail and Supabase
At [claude.ai](https://claude.ai) → Settings → Connectors, connect **Gmail** and **Supabase** (authorize your Supabase project).

### 4. Create Routine 1 - Cleanup Gmail
At [claude.ai/code/routines](https://claude.ai/code/routines) → New routine, fill each section:

| Section | What to put |
|---|---|
| **Name** | `Cleanup Gmail` (cosmetic) |
| **Instructions** | `Read routines/cleanup_gmail.md from the attached repo and follow the block between the >>> and <<< markers exactly, using the SETTINGS at the top. The classification rules are in prompts/classify_prompt.md.` |
| **Repo** | Attach your fork |
| **Connectors** | **Gmail + Supabase** only |
| **Trigger** | **Weekly**, one trigger (e.g. Mon 8am) - the routine self-paces |
| **Behavior** | Defaults |
| **Notifications** | **Push on** - how you get the "review by" and "done" pings |
| **Permissions** | Leave **"Allow unrestricted git push" OFF** |
| **Environment** | Leave **empty** - tuning values live in the repo SETTINGS block |

For a first test, set `LOOKBACK_DAYS=3` in the SETTINGS block, then use **Run now**.

### 5. Create Routine 2 - Refine Cleanup Prompt
New routine again:

| Section | What to put |
|---|---|
| **Name** | `Refine Cleanup Prompt` |
| **Instructions** | `Read routines/refine_cleanup_prompt.md from the attached repo and follow the block between the >>> and <<< markers exactly. Open a Pull Request; never merge it yourself or edit main.` |
| **Repo** | Attach your fork (this is your GitHub access - GitHub is not a separate connector) |
| **Connectors** | **Supabase** only |
| **Trigger** | **Custom** cron `0 9 1 * *` (9am on the 1st) |
| **Behavior** | Defaults |
| **Notifications** | **Push on** |
| **Permissions** | Leave **"Allow unrestricted git push" OFF** |
| **Environment** | Leave **empty** |

## How to test?

Use **Run now** to test without waiting for the schedule:

1. **First run** → it classifies: a `To Delete` label appears, nothing is trashed
2. **Untick a couple of emails** to simulate rescuing them
3. **Force the delete phase** - in Supabase run `UPDATE cleaner_state SET pending_since = now() - interval '4 days' WHERE id = 1;` then **Run now** → it trashes what's still labeled and writes to your `cleaner_*` tables

Open each run's **session transcript** to see exactly what it did.

## Environment Variables

No separate env-var field exists in routines, so these live in the **SETTINGS block at the top of the `cleanup` routine's instructions** - edit the numbers there.

| Variable | Default | What it does |
|---|---|---|
| `CYCLE_DAYS` | `7` | How often a fresh cycle starts. `7` = weekly. Keep **≤ 7 on free Supabase** (it pauses after 7 idle days) |
| `DELETE_AFTER_DAYS` | `3` | Review window - days between proposal and trash. Must be **< `CYCLE_DAYS`** |
| `REMIND_EVERY_HOURS` | `24` | Most often a reminder is sent while a window is open - prevents spam |
| `CHUNK_SIZE` | `100` | Emails classified per batch. Big inboxes are chunked - no per-run cap |
| `LOOKBACK_DAYS` | `30` | First run only: days of past mail to scan before there's any history |
| `GRADUATE_ROUNDS` | `2` | Confirmed-delete cycles in a row before a rarely-read sender auto-deletes |

## How it decides what to delete

All in [`prompts/classify_prompt.md`](prompts/classify_prompt.md): a few hard rules (NEVER-DELETE, ALWAYS-KEEP, ALWAYS-DELETE) plus judgment for the rest - it keeps when unsure, and leans toward deleting heavy, low-value mail from senders you rarely read. It scans every category (Primary, Promotions, Updates, Social, Forums) but **never touches Spam or Trash**. Edit that file to change behavior.

## Reviewing and rescuing mail

One label, **`To Delete`** - the only one you ever touch.

- **When a cleanup runs** you get a Claude notification and a **`To Delete (N)`** label in Gmail
- **To keep something:** remove the `To Delete` label from it, any time before the delete day
- **To delete something yourself:** add the `To Delete` label to it
- **On the delete day** whatever is still labeled goes to Trash - recoverable for 30 days

The routine remembers what it proposed (in Supabase, not a visible label) and compares it to what's still labeled on the delete day:

| What happened | Read as |
|---|---|
| Proposed **and** still labeled | You **confirmed** the delete |
| Proposed but you **removed** the label | You **rescued** it (keep) |
| Labeled but **not** proposed | You **added** it yourself |

**What categories are for.** Each email gets a short category tag (`offer`, `receipt`, `hr`, `security`, ...). They aren't Gmail labels - they live in Supabase and drive three things: per-category-and-sender trust/graduation, balanced few-shot variety, and category-level protection (e.g. never delete `hr`).

## Privacy & safety

- Your email patterns live only in **your** Supabase project - never in this repo
- The model sees only metadata + a short snippet - **never full bodies or attachments**
- The routine only applies the **TRASH** label - it can never permanently delete

The "snippet" is the short preview **Gmail itself generates** (the API's `snippet` field), truncated to ≤300 characters.

## Repo contents

| File | What it is |
|---|---|
| [`prompts/classify_prompt.md`](prompts/classify_prompt.md) | The classification prompt (rules + judgment) |
| [`routines/cleanup_gmail.md`](routines/cleanup_gmail.md) | Routine 1 - classify → remind → delete → learn |
| [`routines/refine_cleanup_prompt.md`](routines/refine_cleanup_prompt.md) | Routine 2 - monthly prompt-improvement PR |
| [`schema.sql`](schema.sql) | The Supabase tables (run once) |

Issues and PRs welcome.
