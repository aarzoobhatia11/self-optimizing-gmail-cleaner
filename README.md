# self-optimizing-gmail-cleaner

*A Gmail cleanup that runs as a **Claude routine** and **optimizes its own classifier prompt** from
your keep/delete feedback — so it needs less of your approval every week.*

## What it does
A **Claude routine** scans your Gmail on a schedule and labels the mail it thinks you'd delete
(promotions, expired notices, low-value bulk). You glance at the `To Delete` label in Gmail and
**untick anything you want to keep** — or **add that label to anything else you want gone** — and a
couple of days later it moves everything still under the label to Trash (recoverable for 30 days).
That's the whole review.

**Here's what makes this Gmail cleaner different:** mail that's useful *now* but junk *later* — a flight
booking, an event ticket, a time-limited offer — isn't deleted early or hoarded forever. It's parked in
a **carry-forward queue** and quietly brought back for deletion only once it **expires**. And every
keep/untick you make **teaches it your taste**, so it learns to need less of your review over time.

**How it runs:** your memory lives in your own **free Supabase database**, the routine runs on whatever
**frequency you set**, and it **notifies you in the Claude app** when there's something to review.
Because it runs as a Claude routine, there are **no API credits to buy** and **no server to host** —
and nothing here ever exposes your email.

---

## 🔄 How it self-optimizes
The cleaner gets better at predicting *you* through four feedback loops, all driven by the keep/delete
edits you make each cycle:

1. **Every decision becomes an example, and the best 5 are sent as few-shot.** Each email you keep or
   untick is saved to your Supabase memory. On the next run it pulls your recent decisions, ranks them
   **corrections first → confident-but-wrong → most recent**, and picks the **top 5** — kept varied (a
   mix of keeps *and* deletes across different categories, never 5 of the same kind). Those 5 are
   injected into the classifier prompt as **few-shot examples**, so the model copies *your* judgment.
   The cap is deliberately small (~5): more examples bias the model rather than help.
2. **Repeat offenders graduate to auto-delete.** If you confirm deleting a rarely-read sender for a few
   cycles in a row, that sender is promoted to "always delete" and stops needing your review at all.
3. **Time-sensitive keeps wait in a deferred queue.** A booking, ticket, or offer you keep is parked
   with an expiry date and quietly resurfaced for deletion only once it's stale — so kept mail doesn't
   pile up forever.
4. **A monthly PR sharpens the prompt.** The `refine` routine looks for *patterns* in your corrections
   and opens a **GitHub Pull Request** improving the classifier's wording — which you review and merge.

```
        ┌──────────────────────────────────────────────────────────┐
        │                                                          │
        ▼                                                          │
   classify  ──►  you keep / untick  ──►  saved as examples + trust │
   (proposes)        (your edits)         (corrections first)      │
        ▲                                          │               │
        │                                          ▼               │
        └────────  next run is smarter  ◄──  graduate senders,  ───┘
                                              resurface expired,
                                              monthly prompt PR
```

**Net effect:** the recurring mail starts handling itself, and the pile that actually needs your eyes
**shrinks toward just genuinely-new senders** — so reviewing becomes optional, not a chore. *(The
approval gate never disappears — it's your safety net — you just stop needing to use it.)*

---

## How it works

```
  Routine "cleanup" — self-pacing: on each run it does the one phase that's due.
   ┌─ CLASSIFY      → scans new mail, labels To Delete, notifies "review by <date>"
   ├─ REMIND        → "N still pending, trashed on <date>"  (at most once a day)
   └─ DELETE+LEARN  → trashes what's still labeled, learns from your edits, notifies a summary

  You: open the To Delete label in Gmail — untick anything to keep, or add the label to
       anything else you want gone. That's the whole review.

  Memory (Supabase): your rules, few-shot examples, trust scores, and the carry-forward queue.
  Routine "refine" (monthly): opens a GitHub PR improving the prompt from your corrections — you merge.
```

- **Trash only** — nothing is permanently deleted (30-day recovery).
- **Metadata only** — only sender, subject, a ~300-char snippet, and size go to the model; never full
  bodies or attachments.
- **Self-pacing** — the routine decides what to do from timestamps in its memory, so extra triggers are
  harmless (see [🕒 Scheduling & frequency](#-scheduling--frequency)).

---

## 🧰 Tools & accounts you need

| Tool / account | What it's for |
|---|---|
| **Claude — Pro or Max plan** | Runs the routines in Claude's cloud; no server of your own and no API credits to buy. |
| **Claude app** | Where you create & watch routines and get review notifications. Use the web ([claude.ai/code](https://claude.ai/code)), the desktop app ([Mac/Windows](https://claude.ai/download)), or the CLI — any works. |
| **Gmail account + Gmail connector** | Lets the routine read mail *metadata*, manage the `To Delete` label, and move mail to Trash. |
| **Supabase — free account + connector** | Your private memory database (rules, examples, trust, deferred queue). |
| **GitHub** *(optional)* | Only for the monthly `refine` routine, which opens prompt-improvement PRs. |

---

## Setup (~15 minutes)

**1. Fork or clone this repo** (safe to keep public — no personal data is stored here).

**2. Create your memory database.** In [Supabase](https://supabase.com), create a free project → open
the **SQL Editor** → paste and run [`schema.sql`](schema.sql). This creates the `cleaner_*` tables.

**3. Connect the connectors in Claude.** At [claude.ai](https://claude.ai) → Settings → Connectors,
connect **Gmail** and **Supabase** (authorize your Supabase project). *(See [🧰 Tools & accounts](#-tools--accounts-you-need).)*

**4. Create Routine 1 — `cleanup`.** At [claude.ai/code/routines](https://claude.ai/code/routines) →
New routine:
- **Attach this repo**, add the **Gmail** and **Supabase** connectors.
- Paste the instructions from [`routines/cleanup_gmail.md`](routines/cleanup_gmail.md) (between the `>>>` markers).
- Set the **env vars** — see [⚙️ Settings explained](#️-settings-explained-environment-variables).
- **Trigger: weekly** (e.g. Mon 8am). One weekly trigger is enough — the routine paces itself
  (details in [🕒 Scheduling & frequency](#-scheduling--frequency)).
  *(For a first test, set `LOOKBACK_DAYS=3` and use "Run now".)*

**5. (Optional) Create Routine 2 — `refine`.** Same flow with [`routines/refine_cleanup_prompt.md`](routines/refine_cleanup_prompt.md),
connectors **Supabase + GitHub**, a **monthly** trigger. It opens a PR each month suggesting prompt
improvements from your corrections; you review the diff and merge.

---

## ⚙️ Settings explained (environment variables)

Set these on the `cleanup` routine. The defaults suit a weekly personal-inbox cleanup.

| Variable | Default | What it does |
|---|---|---|
| `CYCLE_DAYS` | `7` | How often a fresh cleanup cycle starts (the gap between CLASSIFY runs). `7` = weekly. Keep **≤ 7 on free-tier Supabase** (see Scheduling & frequency). |
| `DELETE_AFTER_DAYS` | `3` | Your **review window** — days between a proposal and the actual trash. Must be **less than `CYCLE_DAYS`**; recommended minimum **2**. |
| `REMIND_EVERY_HOURS` | `24` | The most often a reminder is sent while a window is open — prevents notification spam if the routine fires frequently. |
| `CHUNK_SIZE` | `100` | How many emails the classifier handles per batch. Large inboxes are processed in chunks instead of one giant call — there's no per-run cap. |
| `LOOKBACK_DAYS` | `30` | **First run only:** how many days of past mail to scan before there's any history. After that it scans since the last cleanup. |
| `GRADUATE_ROUNDS` | `2` | How many cycles in a row a rarely-read sender must be confirmed-deleted before it auto-deletes without asking. |

---

## ✅ Your review: approving deletes & rescuing mail

The cleaner uses a **single Gmail label, `To Delete`** — that's the only label you ever see or touch.

- **When a cleanup runs** you get a Claude notification and a **`To Delete (N)`** label appears in Gmail.
- **To save a mail from deletion:** open the `To Delete` label and **remove it** from anything you want to keep — any time before the delete day.
- **To delete something yourself:** add the `To Delete` label to anything from this cycle you want gone.
- **On the delete day** the routine trashes whatever is *still* under `To Delete` and sends a summary. Everything stays in **Trash for 30 days** if you change your mind.

**How it learns from your edits.** The routine remembers what it proposed (in its Supabase memory — not
as a label you see), then compares that to what's still under `To Delete` on the delete day:

| What happened | The routine reads it as |
|---|---|
| It proposed it **and** it's still under `To Delete` | You **confirmed** the deletion. |
| It proposed it but you **removed** the label | You **rescued** it (keep). |
| It's under `To Delete` but the routine **didn't** propose it | You **added** it yourself. |

### What categories are for
Every email the classifier looks at gets a short **category** tag — `offer`, `receipt`, `booking`,
`hr`, `security`, `pm_material`, `other`, and so on. Categories aren't Gmail labels; they live in the
model's output and your Supabase memory, and they do three jobs:
- **Smarter learning** — trust and "graduate to auto-delete" are tracked *per category + sender*, so a
  sender you delete as `offer` is judged separately from one you keep as `receipt`.
- **Balanced examples** — few-shot examples are picked to span *different* categories, so the model sees
  variety instead of five of the same kind.
- **Category-level rules** — you can protect a whole category (e.g. never delete anything `hr`).

---

## 🕒 Scheduling & frequency

**Recommended: one weekly trigger** (e.g. Mon 8am). You always get at least `DELETE_AFTER_DAYS`
(default 3 days) to review before anything is trashed, and firing it more often than weekly is safe —
reminders are throttled and any extra runs simply do nothing.

**Want it less often than weekly (e.g. monthly)?** The free Supabase tier pauses a project after 7 days
with no queries, so either use **Supabase Pro** (never pauses) or add a small **keep-alive ping** — a
tiny query every few days that keeps the database awake.

There's **no per-run email cap** — each run cleans everything new since the last one. The only
recommendation is to **run it weekly**.

**How different schedules behave** (`CYCLE_DAYS=7`, `DELETE_AFTER_DAYS=3`):

| You schedule… | Notifications per week | Review time before delete |
|---|---|---|
| Weekly | ~2 (ready + done) | full 7 days |
| Daily | ~4 (ready + ~2 reminders + done) | 3 days |
| Hourly / every 2h | ~5 — throttles absorb the rest | 3 days |

---

## How it decides what to delete
All in [`prompts/classify_prompt.md`](prompts/classify_prompt.md): a few hard rules (NEVER-DELETE,
ALWAYS-KEEP, ALWAYS-DELETE) plus judgment for everything else (it keeps when unsure, and leans toward
deleting heavy low-value mail and senders you rarely read). It scans all of your mail — Primary,
Promotions, Updates, Social, Forums — but **never touches Spam or Trash**. Tweak that file to change
behavior.

---

## Privacy & safety
- Your email patterns live only in **your** Supabase project — never in this repo.
- The model only ever sees metadata + a short snippet — **never full email bodies or attachments**.
- The routine only applies the **TRASH** label; it can never permanently delete.

**How the "snippet" is obtained:** the snippet is the short plaintext preview **Gmail itself generates**
(the Gmail API's `snippet` field — the same one-line preview you see in your inbox list), which the
routine truncates to ≤300 characters. The model never receives the full message body.

---

## Testing after setup
Use **"Run now"** to test without waiting for the schedule:
1. **First run** → it classifies: a `To Delete` label appears in Gmail, nothing is trashed.
2. **Untick a couple of emails** (remove the `To Delete` label) to simulate rescuing them.
3. **Force the delete phase now** — in Supabase run:
   `UPDATE cleaner_state SET pending_since = now() - interval '4 days' WHERE id = 1;`
   then **Run now** → it trashes whatever's still under `To Delete` and writes to your `cleaner_*` tables.

Open each run's **session transcript** to see exactly what it did (a green status means it ran, not that
it succeeded).

---

## Repo contents
| File | What it is |
|---|---|
| `prompts/classify_prompt.md` | The classification prompt (rules + judgment). |
| `routines/cleanup_gmail.md` | Routine 1 — classify → remind → delete → learn (paste into the routine). |
| `routines/refine_cleanup_prompt.md` | Routine 2 — monthly prompt-improvement PR. |
| `schema.sql` | The Supabase tables (run once). |
| `CLAUDE.md` | Project context for contributors. |

Issues and PRs welcome. Licensed under the MIT License.
