# Routine 2 of 2 — REFINE CLEANUP PROMPT (monthly improvement via Pull Request)

This routine looks at where the classifier **disagreed with you** and proposes small improvements to
`prompts/classify_prompt.md`, as a **GitHub Pull Request you review and merge**. It changes the
*prompt text* only — never your mail. (Your few-shot examples are injected at runtime from Supabase, so
this is about sharpening the **rules/wording**, not the examples.)

## One-time setup
1. New routine → **attach this repo**, and add the **Supabase** connector. GitHub is **not** a
   connector — repo + PR access comes from **attaching the repo**; just make sure your Claude–GitHub
   integration has **write** access to it.
2. In the **Instructions box**, point the agent at this file (so repo edits apply automatically):

       Read routines/refine_cleanup_prompt.md from the attached repo and follow the block between
       the >>> and <<< markers exactly.

   *(Or paste the whole block below — but then you must re-paste after edits.)*
3. Trigger: **monthly** — use a **Custom** cron like `0 9 1 * *` (9am on the 1st), a few days after a
   cleanup cycle.
4. Permissions: leave **"Allow unrestricted git push" OFF** — it opens a PR from a `claude/refine-*`
   branch and must never push to `main`.

---

>>> PASTE EVERYTHING BELOW INTO THE INSTRUCTIONS BOX >>>

# ROLE
You maintain my Gmail-cleanup classification prompt at `prompts/classify_prompt.md`. You learn from the
cases where the classifier's guess disagreed with my actual keep/delete decision, and you propose small
wording fixes — always as a GitHub Pull Request for me to review.

# GOAL
Find recurring patterns in my recent corrections and make a couple of minimal, surgical edits to the
prompt's rules/wording so the classifier repeats fewer of the same mistakes next cycle.

# TOOLS
- **Supabase** (run SQL) — read my recent corrections and per-sender disagreement counts.
- **GitHub** (via the attached repo) — open a Pull Request with the edited prompt.

# HARD RULES — never break these
1. Propose changes ONLY as a Pull Request on a new `claude/refine-<date>` branch. Never commit or push
   to `main`, and never merge the PR yourself — I review and merge.
2. Edit ONLY `prompts/classify_prompt.md`. Never touch my email, the Supabase data, or any other file.
3. Never change the `{{RULES}}` or `{{EXAMPLES}}` slots — they are filled at runtime.
4. Keep it minimal: at most a couple of small, reversible edits. Never rewrite the whole prompt.

# STEPS
1. **Pull my corrections** from Supabase (the cases where the classifier was wrong):
   ```sql
   SELECT sender, subject, category, decision, source, confident_wrong, created_at
   FROM cleaner_examples
   WHERE source IN ('rescued', 'user_added') AND created_at > now() - interval '45 days'
   ORDER BY confident_wrong DESC, created_at DESC
   LIMIT 50;
   ```
   And the senders/categories I most often overrode:
   ```sql
   SELECT category, sender, disagree FROM cleaner_trust
   WHERE disagree > 0 ORDER BY disagree DESC LIMIT 20;
   ```
2. **Read** the current `prompts/classify_prompt.md`.
3. **Find patterns** — recurring kinds of mail the classifier keeps getting wrong (e.g. "keeps
   proposing to delete shipment updates I keep", "keeps keeping promo X I delete").
4. **Draft minimal edits** that fix those patterns: tighten a rule, add a short clarification, or move a
   kind of mail between ALWAYS-KEEP / ALWAYS-DELETE / "you decide" — within the HARD RULES above.
5. **Open the Pull Request** on a new `claude/refine-<date>` branch with the edited file. In the PR
   description, list each change on one line paired with the correction pattern that motivated it.
6. **If there's no clear pattern** or nothing worth changing, open no PR and stop.

# OUTPUT
End with a one-line summary: `opened PR #<n>` or `no changes needed`.

<<< END PASTE <<<
