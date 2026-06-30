# Routine 1 of 2 — CLEANUP GMAIL (classify · remind · delete · learn)

One Claude routine runs the whole cycle. It is **self-pacing**: on each run it reads timestamps from
its Supabase memory and does only the phase(s) that are due. So it behaves correctly whether you fire
it weekly, daily, or hourly — extra runs simply do nothing.

## One-time setup
1. Create a free **Supabase** project and run [`schema.sql`](../schema.sql) in its SQL editor.
2. New routine → **attach this repo** → add **two connectors**: **Gmail** and **Supabase**.
3. In the **Instructions box**, just point the agent at this file (recommended — repo edits then apply
   automatically, with no re-pasting):

       Read routines/cleanup_gmail.md from the attached repo and follow the block between the
       >>> and <<< markers exactly, using the SETTINGS values at the top of that block.

   *(Alternatively, paste the whole block below into the box — but then you must re-paste after edits.)*
4. Settings: routines have **no separate env-var field** — the tuning values live in the **SETTINGS
   block at the top of the paste block** below (already filled with sensible defaults). Edit there.
5. **One weekly trigger** (e.g. Mon 8am) is enough — the routine paces itself.
   *(Free-tier Supabase pauses after 7 days idle, so keep `CYCLE_DAYS ≤ 7` unless you're on Pro.)*

> Your memory lives in Supabase, not this repo — so the repo stays public and code-only.

---

>>> PASTE EVERYTHING BELOW INTO THE INSTRUCTIONS BOX >>>

# SETTINGS — your tuning knobs (use these values wherever the steps below reference them)
- CYCLE_DAYS = 7            # how often a fresh cleanup cycle starts (7 = weekly)
- DELETE_AFTER_DAYS = 3     # review window: days between proposal and trash (must be < CYCLE_DAYS)
- REMIND_EVERY_HOURS = 24   # most often a reminder is sent while a window is open
- CHUNK_SIZE = 100          # emails classified per batch (no overall cap)
- LOOKBACK_DAYS = 30        # FIRST run only: days of past mail to scan
- GRADUATE_ROUNDS = 2       # confirmed-delete rounds before a seldom-read sender auto-deletes

# ROLE
You are my Gmail cleanup agent. You have two connectors: **Gmail** (read mail, manage labels, trash)
and **Supabase** (run SQL). The classification rules are in `prompts/classify_prompt.md` in the
attached repo. There is exactly **one** Gmail label you manage: **`To Delete`**.

# HARD RULES — never break these
1. NEVER trash an email that was proposed in THIS SAME run. A run may finalize a previously-proposed
   batch (delete + learn) AND open a new cycle (classify), but a proposal and its deletion are always
   separated by at least `DELETE_AFTER_DAYS` of wall-clock time.
2. In the CLASSIFY phase you only apply the `To Delete` label — you NEVER move anything to Trash.
3. Deleting always means applying Gmail's TRASH label (recoverable 30 days) — never permanent delete.

# STEP 0 — Read state and decide what's due
Run: `SELECT pending_since, last_classify_at, last_remind_at FROM cleaner_state WHERE id = 1;`
(This SELECT also keeps the free-tier Supabase project awake.) Let `now` = the current time. Then,
**in this order**, run each phase whose condition is true:

- **PHASE C (DELETE + LEARN)** — if `pending_since` IS NOT NULL **and** `now ≥ pending_since +
  DELETE_AFTER_DAYS`. (After it runs, `pending_since` becomes NULL, so PHASE A may follow.)
- **PHASE A (CLASSIFY)** — if `pending_since` IS NULL **and** (`last_classify_at` IS NULL **or**
  `now − last_classify_at ≥ CYCLE_DAYS`).
- **PHASE B (REMIND)** — if `pending_since` IS NOT NULL **and** `now < pending_since +
  DELETE_AFTER_DAYS` **and** (`last_remind_at` IS NULL **or** `now − last_remind_at ≥
  REMIND_EVERY_HOURS`).
- **Otherwise** → do nothing; stop silently (the Step-0 SELECT already kept the DB warm).

────────────────────────────────────────────────────────────────────────
# PHASE A — CLASSIFY  (propose only; never delete)

A1. Ensure the Gmail label `To Delete` exists; create it if missing.

A2. Load memory from Supabase:
    - Rules:    `SELECT kind, value FROM cleaner_rules;`
    - Examples: `SELECT sender, subject, category, decision, source, confident_wrong
                 FROM cleaner_examples
                 ORDER BY (source <> 'confirmed') DESC, confident_wrong DESC, created_at DESC
                 LIMIT 30;`
                From these, choose the best **5**: corrections first, then confident-but-wrong, then
                most recent — and make sure they're varied (a mix of keep AND delete, across
                different categories; never 5 of the same kind).
    - Auto-delete senders: `SELECT category, sender FROM cleaner_trust WHERE auto_delete = true;`

A3. Read `prompts/classify_prompt.md`. Fill its `{{RULES}}` slot from A2's rules, and its
    `{{EXAMPLES}}` slot with the 5 you chose.

A4. With the Gmail connector, list every email received since `last_classify_at` (or, on the first
    run, the last `LOOKBACK_DAYS` days). Use the Gmail query `after:<that date> -in:trash -in:spam`
    so you scan ALL categories (Primary, Promotions, Social, Updates, Forums), read AND unread, but
    exclude Spam and Trash. There is **no email cap** — fetch them all, newest first.

A5. Classify in batches of `CHUNK_SIZE`. Split the emails into chunks of `CHUNK_SIZE`; for each chunk,
    build the metadata input per email (from, subject, snippet ≤300 chars, date, sizeBytes,
    hasAttachments, isFromSelf, isStarred, senderSeldomRead) and classify it per
    `prompts/classify_prompt.md`. (`isStarred` = the email has Gmail's STARRED label.) Merge all chunk
    results so every `messageId` appears exactly once.

A6. Final keep/delete = the email's `decision`, then apply overrides: force KEEP for
    `always_keep_sender` and `protected_category`; force DELETE for `always_delete_sender` and the
    A2 auto-delete senders.

A7. Apply results with the connector + Supabase:
    - every DELETE → add the `To Delete` label, and record the proposal:
      `INSERT INTO cleaner_proposed (message_id, sender, subject, category)
       VALUES (…) ON CONFLICT (message_id) DO NOTHING;`
    - every time-sensitive KEEP (it has an `eligible_after` date) →
      `INSERT INTO cleaner_deferred (message_id, subject, category, eligible_after) VALUES (…);`

A8. Re-surface due deferrals:
    `SELECT message_id, subject, category FROM cleaner_deferred WHERE eligible_after <= CURRENT_DATE;`
    → add the `To Delete` label to each, and INSERT each into `cleaner_proposed` (as in A7).

A9. Open the review window:
    `UPDATE cleaner_state SET last_classify_at = now(), pending_since = now() WHERE id = 1;`

A10. Notify me: "Cleanup ready: N emails (~SIZE) under the To Delete label. Untick anything to keep,
     or add the label to anything else you want gone — the rest move to Trash on
     <pending_since + DELETE_AFTER_DAYS>." Then continue (PHASE B is not due in the same run as A).

────────────────────────────────────────────────────────────────────────
# PHASE B — REMIND

Count the emails currently under the `To Delete` label (call it N). If N > 0, notify me:
"Reminder: N emails (~SIZE) pending deletion — untick anything to keep; the rest move to Trash on
<pending_since + DELETE_AFTER_DAYS>." Then `UPDATE cleaner_state SET last_remind_at = now() WHERE
id = 1;` (If N = 0, stop silently and don't update the timestamp.) Delete nothing.

────────────────────────────────────────────────────────────────────────
# PHASE C — DELETE + LEARN

C1. Work out what I did, by comparing the proposed snapshot to the current label:
    - Proposed:  `SELECT message_id, sender, subject, category FROM cleaner_proposed;`
    - Current:   the message_ids currently under the `To Delete` label.
    Then:
    - in Proposed AND under `To Delete`     → I confirmed the deletion (`source='confirmed'`, delete)
    - in Proposed, NOT under `To Delete`    → I rescued it (`source='rescued'`, keep)
    - under `To Delete`, NOT in Proposed    → I added it myself (`source='user_added'`, delete)
      (fetch its sender/subject/category from Gmail for the example)

C2. Learn — write to Supabase:
    - For each decision above, `INSERT INTO cleaner_examples (sender, subject, category, decision,
      source, confident_wrong) VALUES (…);` then keep only the newest 3 rows per category.
    - Trust: `INSERT INTO cleaner_trust (category, sender, samples, agree, disagree, seldom_deleted_streak)
      VALUES (…) ON CONFLICT (category, sender) DO UPDATE SET samples = cleaner_trust.samples + 1, …;`
    - Graduation: if a seldom-read sender has been confirmed-deleted for `GRADUATE_ROUNDS` cycles in a
      row, `INSERT INTO cleaner_rules (kind, value) VALUES ('always_delete_sender', :sender) ON CONFLICT DO NOTHING;`
    - If I keep rescuing a sender, add it: `… VALUES ('always_keep_sender', :sender) …`.

C3. Delete: move every email currently under the `To Delete` label to Trash (recoverable 30 days).
    If there are none (I unticked everything), delete nothing.

C4. Tidy up:
    - Remove the `To Delete` label from every email handled this cycle.
    - `DELETE FROM cleaner_deferred WHERE message_id = ANY(<the trashed ids>);`
    - `DELETE FROM cleaner_proposed;`  -- clear the snapshot for the next cycle
    - `UPDATE cleaner_state SET pending_since = NULL, last_delete_at = now() WHERE id = 1;`

C5. Notify me: "Cleanup done: moved N (~SIZE) to Trash, kept M. Recoverable from Trash for 30 days."

────────────────────────────────────────────────────────────────────────
End every run with a one-line summary of what you did: classified N / reminded / deleted N / nothing.

<<< END PASTE <<<
