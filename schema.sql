-- Gmail Cleaner - Supabase schema.
-- Run this ONCE in your Supabase project's SQL editor. It creates the tables the cleanup routine
-- uses as its private memory. No personal data ever lives in this (public) git repo - it lives only
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

-- Proposed snapshot: the emails THIS cycle proposed for deletion, plus the metadata the model saw and
-- its confidence. Short-lived: written when labels are applied, read + cleared on delete day (used to
-- learn what you confirmed / rescued / added, and to write the permanent decision log).
create table if not exists cleaner_proposed (
  message_id         text primary key,
  sender             text,
  subject            text,
  category           text,
  snippet            text,
  size_bytes         bigint,
  is_starred         boolean,
  is_from_self       boolean,
  sender_seldom_read boolean,
  email_date         date,
  model_confidence   numeric,      -- the model's confidence in its (delete) call, 0..1
  proposed_at        timestamptz default now()
);

-- Decision log: one row per reviewed email = the full labelled memory. Stores the metadata the model
-- saw, what it PREDICTED (+ confidence), and what you ACTUALLY decided. This single table feeds both
-- the weekly few-shot example picks AND the monthly evaluation in the refine routine.
create table if not exists cleaner_decisions (
  id                 bigint generated always as identity primary key,
  message_id         text not null,
  decided_at         timestamptz default now(),
  sender             text,
  subject            text,
  snippet            text,
  size_bytes         bigint,
  is_starred         boolean,
  is_from_self       boolean,
  sender_seldom_read boolean,
  email_date         date,
  category           text,
  model_decision     text check (model_decision in ('keep', 'delete')),  -- what the prompt predicted
  model_confidence   numeric,                                            -- 0..1 (NULL for user_added)
  my_decision        text check (my_decision in ('keep', 'delete')),     -- ground truth (your call)
  outcome            text check (outcome in ('confirmed', 'rescued', 'user_added'))
);

-- Hard rules: senders/categories that are always kept or always deleted.
create table if not exists cleaner_rules (
  id       bigint generated always as identity primary key,
  kind     text not null check (kind in ('always_keep_sender', 'always_delete_sender', 'protected_category')),
  value    text not null,
  added_at timestamptz default now(),
  unique (kind, value)
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
