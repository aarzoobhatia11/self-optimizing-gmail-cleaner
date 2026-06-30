-- Gmail Cleaner — Supabase schema.
-- Run this ONCE in your Supabase project's SQL editor. It creates the tables the cleanup routine
-- uses as its private memory. No personal data ever lives in this (public) git repo — it lives only
-- in your own Supabase project.

-- Run state: a single row that drives the self-pacing phase logic (all timestamps).
create table if not exists cleaner_state (
  id               int primary key default 1,
  pending_since    timestamptz,   -- when the current review window opened; NULL = no open window
  last_classify_at timestamptz,   -- when a batch was last proposed (the "scan since" anchor)
  last_remind_at   timestamptz,   -- last reminder sent (drives the reminder throttle)
  last_delete_at   timestamptz    -- last finalize / delete
);
insert into cleaner_state (id) values (1) on conflict (id) do nothing;

-- Proposed snapshot: what the last CLASSIFY run labeled "To Delete". Replaces the old second Gmail
-- label — the routine compares this to what's still under "To Delete" on the delete day to learn
-- which mail you confirmed, rescued, or added yourself. Cleared after each delete.
create table if not exists cleaner_proposed (
  message_id  text primary key,
  sender      text,
  subject     text,
  category    text,
  proposed_at timestamptz default now()
);

-- Hard rules: senders/categories that are always kept or always deleted.
create table if not exists cleaner_rules (
  id       bigint generated always as identity primary key,
  kind     text not null check (kind in ('always_keep_sender', 'always_delete_sender', 'protected_category')),
  value    text not null,
  added_at timestamptz default now(),
  unique (kind, value)
);

-- Few-shot examples: your past keep/delete decisions, used to teach the classifier.
create table if not exists cleaner_examples (
  id              bigint generated always as identity primary key,
  sender          text,
  subject         text,
  category        text,
  decision        text check (decision in ('keep', 'delete')),
  source          text,                    -- 'confirmed' | 'rescued' | 'user_added'
  confident_wrong boolean default false,   -- model was confident but you overrode it (high-signal)
  created_at      timestamptz default now()
);

-- Trust counters: per (category, sender), drive graduation toward auto-delete.
create table if not exists cleaner_trust (
  category              text not null,
  sender                text not null,
  samples               int default 0,
  agree                 int default 0,
  disagree              int default 0,
  seldom_deleted_streak int default 0,     -- consecutive seldom-read-and-deleted cycles
  auto_delete           boolean default false,
  updated_at            timestamptz default now(),
  primary key (category, sender)
);

-- Carry-forward queue: kept-but-time-sensitive mail to re-surface once it expires.
create table if not exists cleaner_deferred (
  message_id     text primary key,
  subject        text,
  category       text,
  eligible_after date,
  created_at     timestamptz default now()
);
