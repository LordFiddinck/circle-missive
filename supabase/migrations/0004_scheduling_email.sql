-- Phase 4: scheduling and email
--
-- Design notes (see implementation_plan.md Sections 3, 5, and 6):
--   * This is the first migration that needs real Edge Function
--     infrastructure (supabase/functions/), because two things
--     genuinely cannot happen inside Postgres: calling the Resend API,
--     and being woken up on a timer without a human request driving
--     it. Everything else here — the outbox, the scheduler's decision
--     of *what* to send *when*, retries, dedupe, preferences, and
--     bounce/complaint bookkeeping — stays in SQL functions, for the
--     same auditable/transactional/idempotent reasons 0002 and 0003
--     gave for doing state changes as SECURITY DEFINER functions
--     rather than raw client writes.
--   * Two Postgres roles now matter, not just `authenticated`/`anon`:
--     `service_role`, used only by the `scheduler-tick` and
--     `email-worker` Edge Functions (never the browser). Functions
--     that touch the outbox, claim/send mail, or run the scheduler are
--     granted to `service_role` only — the frontend has no business
--     calling them, and RLS alone wouldn't stop an authenticated user
--     from calling `execute`-granted functions.
--   * Scope: the plan's Section 4 schema also describes a stock
--     question bank and AI-drafted recommended questions, but Section
--     9's phase breakdown doesn't list them under Phase 4 (they're
--     absent from that phase's bullets and exit criteria) — they stay
--     out of scope here and remain future work, alongside export/
--     deletion requests. This migration is scoped to exactly Phase 4's
--     stated deliverables: next_action_at, the scheduler, the outbox/
--     worker/templates/retries/dedup, Resend, preferences/unsubscribe,
--     and bounce/complaint handling.
--   * Automatic *question selection* is still out of scope (plan
--     Section 1: "automatic selection or voting can come later"), so
--     the scheduler never advances a cycle out of question_collection
--     by itself — it nudges the organizer instead. It does auto-
--     advance answering -> published (the plan's MVP list explicitly
--     includes "Publish an issue at the deadline" and "the next cycle
--     is scheduled automatically"), reusing the exact snapshot logic
--     `publish_cycle()` already used, factored out below so both the
--     organizer's manual early-publish and the scheduler's on-time
--     auto-publish share one code path.

-- ---------------------------------------------------------------------
-- cycles.created_by becomes nullable: a scheduler-started cycle has no
-- human actor. audit_events.actor_id was already nullable for exactly
-- this reason (see 0002); this is the one other NOT NULL that assumed
-- a human was always behind the wheel.
-- ---------------------------------------------------------------------

alter table cycles alter column created_by drop not null;

create index cycles_next_action_idx
  on cycles (next_action_at) where next_action_at is not null;

-- ---------------------------------------------------------------------
-- email_preferences
--   One row per user, created alongside their profile (see the
--   redefined handle_new_user() below). `reminders_enabled` and
--   `announcements_enabled` are the two *optional* categories per the
--   plan ("Optional reminders and announcements; security mail remains
--   mandatory") — everything else (invites, phase-open notices,
--   deadline changes, membership notices) is treated as transactional
--   and always sent regardless of these toggles. `suppressed` is not
--   user-facing: it's set automatically on a hard bounce or spam
--   complaint (see record_email_delivery_event() below) and, unlike
--   the two opt-outs, blocks *all* mail to that address, transactional
--   included — there's no point retrying an address that just bounced.
--   `unsubscribe_token` backs one-click unsubscribe links in mail
--   footers, usable while signed out.
-- ---------------------------------------------------------------------

create table email_preferences (
  user_id uuid primary key references profiles (user_id) on delete cascade,
  reminders_enabled boolean not null default true,
  announcements_enabled boolean not null default true,
  suppressed boolean not null default false,
  unsubscribe_token uuid not null default gen_random_uuid() unique,
  updated_at timestamptz not null default now()
);

alter table email_preferences enable row level security;

create policy "email_preferences_select_own"
  on email_preferences for select
  using (auth.uid() = user_id);

-- Users may flip their own reminders/announcements toggles directly —
-- same reasoning as groups_update_organizer in 0002: a plain field
-- update with no side effects doesn't need a wrapper function. They
-- cannot touch `suppressed` or `unsubscribe_token` themselves; the
-- `with check` below pins every column except the two opt-in flags to
-- its previous value.
create policy "email_preferences_update_own"
  on email_preferences for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create function prevent_email_preferences_privileged_change()
returns trigger
language plpgsql
as $$
begin
  if new.suppressed <> old.suppressed then
    raise exception 'email_preferences.suppressed cannot be set directly.';
  end if;
  if new.unsubscribe_token <> old.unsubscribe_token then
    raise exception 'email_preferences.unsubscribe_token is immutable.';
  end if;
  return new;
end;
$$;

create trigger email_preferences_prevent_privileged_change
  before update on email_preferences
  for each row execute procedure prevent_email_preferences_privileged_change();

create trigger email_preferences_set_updated_at
  before update on email_preferences
  for each row execute procedure set_updated_at();

-- Extend Phase 1's new-user trigger to also create a default
-- preferences row, the same way a profile is created automatically.
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''));

  insert into public.email_preferences (user_id)
  values (new.id);

  return new;
end;
$$;

grant select, update on email_preferences to authenticated;

-- ---------------------------------------------------------------------
-- email_outbox
--   The reliable-delivery queue described in Section 6: a transaction
--   inserts a row (via enqueue_email() below), `email-worker` claims
--   and sends it, success/failure/provider webhook events update it.
--   No RLS policies at all for `authenticated`/`anon` — like
--   `invitations`' token hash, this is operational data no client
--   role should ever read or write; only SECURITY DEFINER functions
--   (owned by the migration role) and `service_role` (which bypasses
--   RLS) touch it.
-- ---------------------------------------------------------------------

create type email_outbox_status as enum (
  'pending',   -- queued, not yet claimed (or retrying after a transient failure)
  'sending',   -- claimed by a worker invocation, send in flight
  'sent',      -- delivered to the provider (see also delivered_at, from webhooks)
  'skipped',   -- deliberately not sent: recipient opted out or is suppressed
  'failed'     -- exhausted retries; a permanent failure, visible to organizers/maintainers
);

create table email_outbox (
  id uuid primary key default gen_random_uuid(),
  -- Encodes "this exact notification, once" — e.g.
  -- 'answer_deadline_reminder:<cycle_id>:<user_id>'. The unique
  -- constraint is what makes retried scheduler ticks and retried
  -- worker invocations safe to run any number of times.
  dedupe_key text not null unique,
  recipient_user_id uuid references profiles (user_id) on delete set null,
  recipient_email text not null,
  template text not null,
  category text not null default 'transactional'
    check (category in ('transactional', 'reminders', 'announcements')),
  payload jsonb not null default '{}'::jsonb,
  group_id uuid references groups (id) on delete cascade,
  status email_outbox_status not null default 'pending',
  attempts int not null default 0,
  max_attempts int not null default 6,
  next_attempt_at timestamptz not null default now(),
  claimed_at timestamptz,
  provider_message_id text,
  last_error text,
  sent_at timestamptz,
  delivered_at timestamptz,
  bounced_at timestamptz,
  complained_at timestamptz,
  created_at timestamptz not null default now()
);

-- What claim_outbox_batch() scans: strictly-pending, due rows.
create index email_outbox_claimable_idx
  on email_outbox (next_attempt_at) where status = 'pending';
create index email_outbox_provider_msg_idx
  on email_outbox (provider_message_id) where provider_message_id is not null;
create index email_outbox_by_group_idx on email_outbox (group_id, template, status);

alter table email_outbox enable row level security;

-- ---------------------------------------------------------------------
-- scheduler_runs
--   One row per scheduler_tick() invocation. This is the "dashboards
--   and alerts" hook from Section 8: get_operational_health() below
--   reports how long it's been since the last completed run, so a
--   monitor hitting the `health` Edge Function can page someone if
--   Supabase Cron stops firing, not just if the database is down.
-- ---------------------------------------------------------------------

create table scheduler_runs (
  id uuid primary key default gen_random_uuid(),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  cycles_examined int,
  emails_enqueued int,
  error text
);

alter table scheduler_runs enable row level security;

create index scheduler_runs_completed_idx on scheduler_runs (completed_at desc);

-- ---------------------------------------------------------------------
-- RPC: enqueue_email
--   The one place a row is ever inserted into email_outbox. Checks
--   suppression and (for the two optional categories) preferences,
--   and still inserts a `skipped` row rather than silently doing
--   nothing — so the dedupe key blocks a later, un-skipped duplicate,
--   and so organizer/maintainer dashboards can see "this would have
--   sent, but the recipient opted out" rather than an unexplained gap.
--   Returns whether a new row was actually inserted (false on a
--   dedupe-key conflict), which callers can ignore or use for
--   diagnostics; nothing in this migration relies on the return value
--   for correctness — the unique constraint is the real guarantee.
-- ---------------------------------------------------------------------

create function enqueue_email(
  p_dedupe_key text,
  p_recipient_user_id uuid,
  p_recipient_email text,
  p_template text,
  p_payload jsonb,
  p_group_id uuid,
  p_category text default 'transactional'
)
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
  v_status email_outbox_status := 'pending';
  v_prefs email_preferences%rowtype;
  v_row_count int;
begin
  if p_recipient_user_id is not null then
    select * into v_prefs from email_preferences where user_id = p_recipient_user_id;
    if found then
      if v_prefs.suppressed then
        v_status := 'skipped';
      elsif p_category = 'reminders' and not v_prefs.reminders_enabled then
        v_status := 'skipped';
      elsif p_category = 'announcements' and not v_prefs.announcements_enabled then
        v_status := 'skipped';
      end if;
    end if;
  end if;

  insert into email_outbox (
    dedupe_key, recipient_user_id, recipient_email, template, category, payload, group_id, status
  )
  values (
    p_dedupe_key, p_recipient_user_id, p_recipient_email, p_template, p_category, p_payload, p_group_id, v_status
  )
  on conflict (dedupe_key) do nothing;

  get diagnostics v_row_count = row_count;
  return v_row_count > 0;
end;
$$;

revoke execute on function
  enqueue_email(text, uuid, text, text, jsonb, uuid, text)
from public;
grant execute on function
  enqueue_email(text, uuid, text, text, jsonb, uuid, text)
to service_role;

-- ---------------------------------------------------------------------
-- Helpers built on enqueue_email(): fan out one notification to every
-- active member, every active organizer, or every active member who
-- hasn't yet submitted all of a cycle's answers. `p_dedupe_suffix`
-- lets a caller distinguish repeat notifications that should each go
-- out once (e.g. change_cycle_deadline() below can be called more
-- than once per cycle; suffixing with the new deadline means each
-- distinct change gets its own notification instead of only the
-- first).
-- ---------------------------------------------------------------------

create function enqueue_group_email(
  p_group_id uuid,
  p_cycle_id uuid,
  p_template text,
  p_payload jsonb,
  p_category text default 'transactional',
  p_dedupe_suffix text default ''
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_member record;
begin
  for v_member in
    select m.user_id, u.email
    from memberships m
    join auth.users u on u.id = m.user_id
    where m.group_id = p_group_id and m.status = 'active'
  loop
    perform enqueue_email(
      format('%s:%s:%s:%s', p_template, coalesce(p_cycle_id::text, p_group_id::text),
             v_member.user_id, p_dedupe_suffix),
      v_member.user_id, v_member.email, p_template,
      p_payload || jsonb_build_object('recipient_user_id', v_member.user_id),
      p_group_id, p_category
    );
  end loop;
end;
$$;

create function enqueue_organizer_email(
  p_group_id uuid,
  p_cycle_id uuid,
  p_template text,
  p_payload jsonb,
  p_category text default 'transactional',
  p_dedupe_suffix text default ''
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_member record;
begin
  for v_member in
    select m.user_id, u.email
    from memberships m
    join auth.users u on u.id = m.user_id
    where m.group_id = p_group_id and m.status = 'active' and m.role = 'organizer'
  loop
    perform enqueue_email(
      format('%s:%s:%s:%s', p_template, coalesce(p_cycle_id::text, p_group_id::text),
             v_member.user_id, p_dedupe_suffix),
      v_member.user_id, v_member.email, p_template,
      p_payload || jsonb_build_object('recipient_user_id', v_member.user_id),
      p_group_id, p_category
    );
  end loop;
end;
$$;

create function enqueue_unsubmitted_member_email(
  p_cycle_id uuid,
  p_group_id uuid,
  p_template text,
  p_payload jsonb,
  p_category text default 'reminders'
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_member record;
begin
  for v_member in
    select distinct m.user_id, u.email
    from memberships m
    join auth.users u on u.id = m.user_id
    where m.group_id = p_group_id and m.status = 'active'
      and exists (
        select 1 from answers a
        join cycle_questions cq on cq.id = a.question_id
        where cq.cycle_id = p_cycle_id
          and a.author_id = m.user_id
          and a.submitted_at is null
      )
  loop
    perform enqueue_email(
      format('%s:%s:%s', p_template, p_cycle_id, v_member.user_id),
      v_member.user_id, v_member.email, p_template,
      p_payload || jsonb_build_object('recipient_user_id', v_member.user_id),
      p_group_id, p_category
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- RPC: claim_outbox_batch / mark_outbox_sent / mark_outbox_failed
--   The `email-worker` Edge Function's three moves: atomically claim a
--   batch (FOR UPDATE SKIP LOCKED so two overlapping worker
--   invocations never send the same row twice), then report success
--   or failure per row. Retry uses capped exponential backoff
--   (2^attempts minutes, capped at 6 hours); once `max_attempts` is
--   reached the row becomes permanently 'failed' rather than retrying
--   forever, per the plan's "permanent failure is marked and shown to
--   an organizer/maintainer."
-- ---------------------------------------------------------------------

create function claim_outbox_batch(p_limit int default 25)
returns setof email_outbox
language sql
security definer set search_path = public
as $$
  update email_outbox
  set status = 'sending', claimed_at = now(), attempts = attempts + 1
  where id in (
    select id from email_outbox
    where status = 'pending' and next_attempt_at <= now()
    order by next_attempt_at
    limit p_limit
    for update skip locked
  )
  returning *;
$$;

create function mark_outbox_sent(p_id uuid, p_provider_message_id text)
returns void
language sql
security definer set search_path = public
as $$
  update email_outbox
  set status = 'sent', sent_at = now(), provider_message_id = p_provider_message_id, last_error = null
  where id = p_id;
$$;

create function mark_outbox_failed(p_id uuid, p_error text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_row email_outbox%rowtype;
  v_backoff interval;
begin
  select * into v_row from email_outbox where id = p_id for update;
  if v_row.id is null then
    return;
  end if;

  if v_row.attempts >= v_row.max_attempts then
    update email_outbox set status = 'failed', last_error = p_error where id = p_id;
    return;
  end if;

  v_backoff := least(
    power(2::float8, v_row.attempts::float8) * interval '1 minute',
    interval '6 hours'
  );

  update email_outbox
  set status = 'pending', last_error = p_error, next_attempt_at = now() + v_backoff
  where id = p_id;
end;
$$;

revoke execute on function claim_outbox_batch(int) from public;
revoke execute on function mark_outbox_sent(uuid, text) from public;
revoke execute on function mark_outbox_failed(uuid, text) from public;
grant execute on function claim_outbox_batch(int) to service_role;
grant execute on function mark_outbox_sent(uuid, text) to service_role;
grant execute on function mark_outbox_failed(uuid, text) to service_role;

-- ---------------------------------------------------------------------
-- RPC: record_email_delivery_event
--   Called by the `resend-webhook` Edge Function after it verifies the
--   provider's signature (never before — see that function for the
--   verification step; this function trusts its caller completely).
--   A hard bounce or spam complaint suppresses *all* future mail to
--   that user, matching the plan's "bounce/complaint handling."
-- ---------------------------------------------------------------------

create function record_email_delivery_event(
  p_provider_message_id text,
  p_event_type text,
  p_occurred_at timestamptz default now()
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_row email_outbox%rowtype;
begin
  select * into v_row from email_outbox where provider_message_id = p_provider_message_id;
  if v_row.id is null then
    return; -- unrecognized message id (e.g. a provider test event) — nothing to reconcile
  end if;

  if p_event_type = 'delivered' then
    update email_outbox set delivered_at = p_occurred_at
    where id = v_row.id and delivered_at is null;

  elsif p_event_type = 'bounced' then
    update email_outbox set bounced_at = p_occurred_at
    where id = v_row.id and bounced_at is null;
    if v_row.recipient_user_id is not null then
      update email_preferences set suppressed = true, updated_at = now()
      where user_id = v_row.recipient_user_id;
    end if;

  elsif p_event_type = 'complained' then
    update email_outbox set complained_at = p_occurred_at
    where id = v_row.id and complained_at is null;
    if v_row.recipient_user_id is not null then
      update email_preferences set suppressed = true, updated_at = now()
      where user_id = v_row.recipient_user_id;
    end if;
  end if;
end;
$$;

revoke execute on function record_email_delivery_event(text, text, timestamptz) from public;
grant execute on function record_email_delivery_event(text, text, timestamptz) to service_role;

-- ---------------------------------------------------------------------
-- RPC: unsubscribe_by_token
--   Backs the one-click unsubscribe link in mail footers. Callable
--   while signed out (the whole point of a mail-footer link), so it
--   authorizes via the token itself rather than auth.uid(). Only ever
--   turns an optional category off — never touches `suppressed`,
--   which is reserved for provider-verified bounce/complaint events.
-- ---------------------------------------------------------------------

create function unsubscribe_by_token(p_token uuid, p_category text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if p_category not in ('reminders', 'announcements') then
    raise exception 'Unknown email category.' using errcode = '22023';
  end if;

  update email_preferences
  set reminders_enabled = case when p_category = 'reminders' then false else reminders_enabled end,
      announcements_enabled = case when p_category = 'announcements' then false else announcements_enabled end,
      updated_at = now()
  where unsubscribe_token = p_token;

  if not found then
    raise exception 'This unsubscribe link is no longer valid.' using errcode = 'P0002';
  end if;
end;
$$;

grant execute on function unsubscribe_by_token(uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- RPC: get_group_email_activity
--   Organizer-only. The in-app half of "dashboards" from Section 8: a
--   per-template/status count for this group's mail, so an organizer
--   can see "reminders are going out" or notice a run of failures
--   without needing database access. (The operational half —
--   cross-group backlog/health for a maintainer — is
--   get_operational_health() below, exposed only via the `health`
--   Edge Function.)
-- ---------------------------------------------------------------------

create function get_group_email_activity(p_group_id uuid)
returns table (
  template text,
  status email_outbox_status,
  message_count bigint,
  most_recent timestamptz
)
language plpgsql
stable
security definer set search_path = public
as $$
begin
  if not is_group_organizer(p_group_id, auth.uid()) then
    raise exception 'Only an organizer can view email activity.' using errcode = '42501';
  end if;

  return query
  select eo.template, eo.status, count(*), max(eo.created_at)
  from email_outbox eo
  where eo.group_id = p_group_id
  group by eo.template, eo.status
  order by eo.template, eo.status;
end;
$$;

grant execute on function get_group_email_activity(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: get_operational_health
--   Backs the `health` Edge Function from Section 8 ("checks
--   dependencies without returning secrets or personal data" — note
--   this returns only counts/timestamps, no email addresses or
--   payload contents). `service_role` only; there is no organizer-
--   scoped version of this because it deliberately spans every group.
-- ---------------------------------------------------------------------

create function get_operational_health()
returns table (
  pending_outbox_count bigint,
  oldest_pending_seconds numeric,
  permanently_failed_count bigint,
  last_scheduler_run_at timestamptz,
  seconds_since_last_scheduler_run numeric
)
language sql
stable
security definer set search_path = public
as $$
  select
    (select count(*) from email_outbox where status in ('pending', 'sending')),
    (select extract(epoch from (now() - min(next_attempt_at))) from email_outbox where status = 'pending'),
    (select count(*) from email_outbox where status = 'failed'),
    (select max(completed_at) from scheduler_runs),
    (select extract(epoch from (now() - max(completed_at))) from scheduler_runs);
$$;

revoke execute on function get_operational_health() from public;
grant execute on function get_operational_health() to service_role;

-- ---------------------------------------------------------------------
-- Scheduling: compute_cycle_next_action_at / the recompute trigger
--   Section 5: "queries all records whose next_action_at <= now()...
--   this supports different schedules without maintaining a cron job
--   per group." This function is the single source of truth for what
--   a cycle's *next* checkpoint is, given its phase and persisted
--   timestamps; a trigger keeps `next_action_at` current whenever
--   those change, and scheduler_tick() re-runs it after handling a
--   cycle so the row doesn't get re-selected on every tick forever.
--
--   Only checkpoints strictly in the future are candidates. If every
--   checkpoint for the current phase has already elapsed (the cycle
--   sat untouched past a deadline — most plausibly an unfinalized
--   question phase, since answering auto-publishes), the function
--   falls back to "check again in a day": this keeps nudging an
--   organizer daily instead of every scheduler tick, without ever
--   losing track of the cycle entirely.
-- ---------------------------------------------------------------------

create function compute_cycle_next_action_at(p_cycle cycles)
returns timestamptz
language plpgsql
stable
as $$
declare
  v_candidates timestamptz[];
  v_next timestamptz;
begin
  if p_cycle.phase = 'question_collection' then
    v_candidates := array[
      p_cycle.question_closes_at - interval '1 day', -- "ending soon" notice
      p_cycle.question_closes_at                     -- organizer nudge if still open
    ];
  elsif p_cycle.phase = 'answering' then
    v_candidates := array[
      p_cycle.answer_due_at - interval '2 days',   -- deadline reminder
      p_cycle.answer_due_at - interval '12 hours', -- final reminder
      p_cycle.answer_due_at                        -- auto-publish + auto-start next cycle
    ];
  else
    return null; -- published / skipped: nothing left to schedule
  end if;

  select min(c) into v_next from unnest(v_candidates) as c where c > now();

  if v_next is null then
    v_next := now() + interval '1 day';
  end if;

  return v_next;
end;
$$;

create function cycles_set_next_action_at()
returns trigger
language plpgsql
as $$
begin
  new.next_action_at := compute_cycle_next_action_at(new);
  return new;
end;
$$;

create trigger cycles_recompute_next_action_at
  before insert or update of phase, question_closes_at, answer_opens_at, answer_due_at
  on cycles
  for each row execute procedure cycles_set_next_action_at();

-- ---------------------------------------------------------------------
-- start_cycle_internal / publish_cycle_internal
--   The actual state-changing work behind start_cycle() and
--   publish_cycle(), factored out so the organizer-triggered RPCs
--   (which check `is_group_organizer` first) and the scheduler's
--   automatic transitions (which have no human actor to check — see
--   the created_by/actor_id nullability change above) share one
--   code path each, rather than two copies that could drift.
--   `p_actor_id => null` means "the scheduler did this", logged as a
--   distinct audit event type so the trail stays honest about who (or
--   what) triggered a change.
-- ---------------------------------------------------------------------

create function start_cycle_internal(p_group_id uuid, p_actor_id uuid)
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_group groups%rowtype;
  v_cycle cycles%rowtype;
  v_next_seq int;
begin
  if exists (
    select 1 from cycles
    where group_id = p_group_id and phase in ('question_collection', 'answering')
  ) then
    raise exception 'This group already has an open cycle.' using errcode = '22023';
  end if;

  select * into v_group from groups where id = p_group_id;
  if v_group.id is null then
    raise exception 'Group not found.' using errcode = 'P0002';
  end if;

  select coalesce(max(sequence_no), 0) + 1 into v_next_seq
  from cycles where group_id = p_group_id;

  insert into cycles (
    group_id, sequence_no, phase, question_opens_at, question_closes_at, created_by
  )
  values (
    p_group_id, v_next_seq, 'question_collection', now(),
    now() + make_interval(days => v_group.question_phase_days), p_actor_id
  )
  returning * into v_cycle;

  perform log_audit_event(
    p_group_id, p_actor_id,
    case when p_actor_id is null then 'cycle_auto_started' else 'cycle_started' end,
    jsonb_build_object('cycle_id', v_cycle.id, 'sequence_no', v_next_seq)
  );

  perform enqueue_group_email(
    p_group_id, v_cycle.id, 'question_collection_opened',
    jsonb_build_object(
      'group_name', v_group.name,
      'cycle_id', v_cycle.id,
      'question_closes_at', v_cycle.question_closes_at
    ),
    'transactional'
  );

  return v_cycle;
exception
  when unique_violation then
    raise exception 'This group already has an open cycle.' using errcode = '22023';
end;
$$;

create or replace function start_cycle(p_group_id uuid)
returns cycles
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_group_organizer(p_group_id, auth.uid()) then
    raise exception 'Only an organizer can start a cycle.' using errcode = '42501';
  end if;

  return start_cycle_internal(p_group_id, auth.uid());
end;
$$;

grant execute on function start_cycle(uuid) to authenticated;
revoke execute on function start_cycle_internal(uuid, uuid) from public;
grant execute on function start_cycle_internal(uuid, uuid) to service_role;

create function publish_cycle_internal(p_cycle_id uuid, p_actor_id uuid)
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
  v_group groups%rowtype;
  v_entries int;
begin
  select * into v_cycle from cycles where id = p_cycle_id for update;
  if v_cycle.id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
  end if;

  if v_cycle.phase = 'published' then
    return v_cycle;
  end if;

  if v_cycle.phase <> 'answering' then
    raise exception 'Only a cycle that is open for answering can be published.'
      using errcode = '22023';
  end if;

  insert into issue_entries (cycle_id, question_id, author_id, body, answer_revision, is_late, published_at)
  select cq.cycle_id, a.question_id, a.author_id, a.body, a.revision, false, now()
  from answers a
  join cycle_questions cq on cq.id = a.question_id
  where cq.cycle_id = p_cycle_id and a.submitted_at is not null
  on conflict (question_id, author_id) do nothing;

  get diagnostics v_entries = row_count;

  update cycles
  set phase = 'published', published_at = now()
  where id = p_cycle_id
  returning * into v_cycle;

  select * into v_group from groups where id = v_cycle.group_id;

  perform log_audit_event(
    v_cycle.group_id, p_actor_id,
    case when p_actor_id is null then 'cycle_auto_published' else 'cycle_published' end,
    jsonb_build_object('cycle_id', p_cycle_id, 'entry_count', v_entries)
  );

  perform enqueue_group_email(
    v_cycle.group_id, p_cycle_id, 'issue_published',
    jsonb_build_object('group_name', v_group.name, 'cycle_id', p_cycle_id, 'sequence_no', v_cycle.sequence_no),
    'announcements'
  );

  return v_cycle;
end;
$$;

create or replace function publish_cycle(p_cycle_id uuid)
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_group_id uuid;
begin
  select group_id into v_group_id from cycles where id = p_cycle_id;
  if v_group_id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
  end if;

  if not is_group_organizer(v_group_id, auth.uid()) then
    raise exception 'Only an organizer can publish a cycle.' using errcode = '42501';
  end if;

  return publish_cycle_internal(p_cycle_id, auth.uid());
end;
$$;

grant execute on function publish_cycle(uuid) to authenticated;
revoke execute on function publish_cycle_internal(uuid, uuid) from public;
grant execute on function publish_cycle_internal(uuid, uuid) to service_role;

-- finalize_questions() gains one thing over its 0003 definition: an
-- "answering opened" notice once the phase actually transitions. The
-- rest of the body is unchanged.
create or replace function finalize_questions(p_cycle_id uuid, p_proposal_ids uuid[])
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
  v_group groups%rowtype;
  v_proposal_id uuid;
  v_position int := 0;
  v_text text;
  v_member record;
  v_distinct_count int;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in.' using errcode = '28000';
  end if;

  select * into v_cycle from cycles where id = p_cycle_id for update;
  if v_cycle.id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
  end if;

  if not is_group_organizer(v_cycle.group_id, auth.uid()) then
    raise exception 'Only an organizer can finalize questions.' using errcode = '42501';
  end if;

  if v_cycle.phase <> 'question_collection' then
    raise exception 'Questions can only be finalized during the question phase.'
      using errcode = '22023';
  end if;

  if p_proposal_ids is null or array_length(p_proposal_ids, 1) is null then
    raise exception 'Select at least one question.' using errcode = '22023';
  end if;

  if array_length(p_proposal_ids, 1) > 50 then
    raise exception 'Select 50 or fewer questions.' using errcode = '22023';
  end if;

  select count(distinct x) into v_distinct_count from unnest(p_proposal_ids) x;
  if v_distinct_count <> array_length(p_proposal_ids, 1) then
    raise exception 'The same question was selected more than once.' using errcode = '22023';
  end if;

  select * into v_group from groups where id = v_cycle.group_id;

  foreach v_proposal_id in array p_proposal_ids loop
    select text into v_text
    from question_proposals
    where id = v_proposal_id and cycle_id = p_cycle_id;

    if v_text is null then
      raise exception 'One of the selected questions does not belong to this cycle.'
        using errcode = '22023';
    end if;

    insert into cycle_questions (cycle_id, proposal_id, text, position)
    values (p_cycle_id, v_proposal_id, v_text, v_position);

    v_position := v_position + 1;
  end loop;

  update cycles
  set phase = 'answering',
      question_closes_at = now(),
      answer_opens_at = now(),
      answer_due_at = now() + make_interval(days => v_group.answer_phase_days)
  where id = p_cycle_id
  returning * into v_cycle;

  for v_member in
    select user_id from memberships where group_id = v_cycle.group_id and status = 'active'
  loop
    insert into answers (question_id, author_id, body)
    select cq.id, v_member.user_id, ''
    from cycle_questions cq
    where cq.cycle_id = p_cycle_id
    on conflict (question_id, author_id) do nothing;
  end loop;

  perform log_audit_event(
    v_cycle.group_id, auth.uid(), 'questions_finalized',
    jsonb_build_object('cycle_id', p_cycle_id, 'question_count', v_position)
  );

  perform enqueue_group_email(
    v_cycle.group_id, p_cycle_id, 'answering_opened',
    jsonb_build_object(
      'group_name', v_group.name, 'cycle_id', p_cycle_id, 'answer_due_at', v_cycle.answer_due_at
    ),
    'transactional'
  );

  return v_cycle;
end;
$$;

grant execute on function finalize_questions(uuid, uuid[]) to authenticated;

-- change_cycle_deadline() gains a "schedule changed" notice to every
-- active member. p_dedupe_suffix is the new deadline itself, so
-- successive changes to the same cycle each notify (see
-- enqueue_group_email()'s comment above).
create or replace function change_cycle_deadline(p_cycle_id uuid, p_new_due_at timestamptz)
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
  v_group groups%rowtype;
begin
  select * into v_cycle from cycles where id = p_cycle_id for update;
  if v_cycle.id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
  end if;

  if not is_group_organizer(v_cycle.group_id, auth.uid()) then
    raise exception 'Only an organizer can change cycle timing.' using errcode = '42501';
  end if;

  if v_cycle.phase not in ('question_collection', 'answering') then
    raise exception 'This cycle is no longer open.' using errcode = '22023';
  end if;

  if p_new_due_at <= now() then
    raise exception 'The new deadline must be in the future.' using errcode = '22023';
  end if;

  if v_cycle.phase = 'question_collection' then
    update cycles set question_closes_at = p_new_due_at
    where id = p_cycle_id returning * into v_cycle;
  else
    update cycles set answer_due_at = p_new_due_at
    where id = p_cycle_id returning * into v_cycle;
  end if;

  select * into v_group from groups where id = v_cycle.group_id;

  perform log_audit_event(
    v_cycle.group_id, auth.uid(), 'cycle_deadline_changed',
    jsonb_build_object('cycle_id', p_cycle_id, 'phase', v_cycle.phase, 'new_due_at', p_new_due_at)
  );

  perform enqueue_group_email(
    v_cycle.group_id, p_cycle_id, 'cycle_schedule_changed',
    jsonb_build_object(
      'group_name', v_group.name, 'cycle_id', p_cycle_id,
      'phase', v_cycle.phase, 'new_due_at', p_new_due_at
    ),
    'transactional',
    p_new_due_at::text
  );

  return v_cycle;
end;
$$;

grant execute on function change_cycle_deadline(uuid, timestamptz) to authenticated;

-- ---------------------------------------------------------------------
-- Invitation emails: create_invitation() and resend_invitation() gain
-- an outbox enqueue each, carrying the one-time raw token (never
-- stored anywhere in cleartext except transiently in this payload —
-- the invitations table itself only ever holds the hash). Rotating
-- the token on resend means its dedupe key changes too, so a resend
-- always enqueues a fresh email rather than deduping against the
-- original invite.
-- ---------------------------------------------------------------------

create or replace function create_invitation(p_group_id uuid, p_email text)
returns table (invitation_id uuid, token text, expires_at timestamptz)
language plpgsql
security definer set search_path = public
as $$
declare
  v_email text := lower(btrim(p_email));
  v_token text;
  v_token_hash text;
  v_expires_at timestamptz := now() + interval '14 days';
  v_invitation_id uuid;
  v_existing_member uuid;
  v_group_name text;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in.' using errcode = '28000';
  end if;

  if not is_group_organizer(p_group_id, auth.uid()) then
    raise exception 'Only an organizer can invite members.' using errcode = '42501';
  end if;

  if v_email = '' or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address.' using errcode = '22023';
  end if;

  select m.user_id into v_existing_member
  from memberships m
  join auth.users u on u.id = m.user_id
  where m.group_id = p_group_id
    and m.status = 'active'
    and lower(u.email) = v_email
  limit 1;

  if v_existing_member is not null then
    raise exception 'This person is already a member of the group.' using errcode = '22023';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  insert into invitations (group_id, email_normalized, token_hash, invited_by, expires_at)
  values (p_group_id, v_email, v_token_hash, auth.uid(), v_expires_at)
  returning id into v_invitation_id;

  perform log_audit_event(
    p_group_id, auth.uid(), 'invitation_created',
    jsonb_build_object('invitation_id', v_invitation_id, 'email', v_email)
  );

  select name into v_group_name from groups where id = p_group_id;

  perform enqueue_email(
    format('group_invitation:%s:%s', v_invitation_id, v_token_hash),
    null, v_email, 'group_invitation',
    jsonb_build_object(
      'group_name', v_group_name, 'invite_token', v_token,
      'invitation_id', v_invitation_id, 'expires_at', v_expires_at
    ),
    p_group_id, 'transactional'
  );

  return query select v_invitation_id, v_token, v_expires_at;
exception
  when unique_violation then
    raise exception 'There is already a pending invite for this email.' using errcode = '23505';
end;
$$;

create or replace function resend_invitation(p_invitation_id uuid)
returns table (token text, expires_at timestamptz)
language plpgsql
security definer set search_path = public
as $$
declare
  v_group_id uuid;
  v_email text;
  v_status invitation_status;
  v_token text;
  v_token_hash text;
  v_expires_at timestamptz := now() + interval '14 days';
  v_group_name text;
begin
  select group_id, email_normalized, status into v_group_id, v_email, v_status
  from invitations where id = p_invitation_id;

  if v_group_id is null then
    raise exception 'Invitation not found.' using errcode = 'P0002';
  end if;

  if not is_group_organizer(v_group_id, auth.uid()) then
    raise exception 'Only an organizer can resend invites.' using errcode = '42501';
  end if;

  if v_status not in ('pending', 'expired') then
    raise exception 'This invite can no longer be resent.' using errcode = '22023';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  update invitations
  set token_hash = v_token_hash,
      expires_at = v_expires_at,
      status = 'pending'
  where id = p_invitation_id;

  perform log_audit_event(
    v_group_id, auth.uid(), 'invitation_resent',
    jsonb_build_object('invitation_id', p_invitation_id)
  );

  select name into v_group_name from groups where id = v_group_id;

  perform enqueue_email(
    format('invitation_reminder:%s:%s', p_invitation_id, v_token_hash),
    null, v_email, 'invitation_reminder',
    jsonb_build_object(
      'group_name', v_group_name, 'invite_token', v_token,
      'invitation_id', p_invitation_id, 'expires_at', v_expires_at
    ),
    v_group_id, 'transactional'
  );

  return query select v_token, v_expires_at;
end;
$$;

-- remove_member() gains a membership-change notice to the person who
-- was removed. Suffixed with today's date: removing and re-inviting
-- someone later should notify again, not dedupe against a stale event.
create or replace function remove_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_target_role membership_role;
  v_organizer_count int;
  v_group_name text;
  v_email text;
begin
  if not is_group_organizer(p_group_id, auth.uid()) then
    raise exception 'Only an organizer can remove members.' using errcode = '42501';
  end if;

  select role into v_target_role
  from memberships
  where group_id = p_group_id and user_id = p_user_id and status = 'active';

  if v_target_role is null then
    raise exception 'That person is not an active member of this group.' using errcode = 'P0002';
  end if;

  if v_target_role = 'organizer' then
    select count(*) into v_organizer_count
    from memberships
    where group_id = p_group_id and role = 'organizer' and status = 'active';

    if v_organizer_count <= 1 then
      raise exception 'A group must keep at least one organizer. Promote another member first.'
        using errcode = '22023';
    end if;
  end if;

  update memberships
  set status = 'removed', left_at = now()
  where group_id = p_group_id and user_id = p_user_id;

  perform log_audit_event(
    p_group_id, auth.uid(), 'member_removed',
    jsonb_build_object('user_id', p_user_id)
  );

  select name into v_group_name from groups where id = p_group_id;
  select email into v_email from auth.users where id = p_user_id;

  perform enqueue_email(
    format('membership_changed:removed:%s:%s:%s', p_group_id, p_user_id, now()::date),
    p_user_id, v_email, 'membership_changed',
    jsonb_build_object('group_name', v_group_name, 'change', 'removed'),
    p_group_id, 'transactional'
  );
end;
$$;

-- ---------------------------------------------------------------------
-- RPC: scheduler_tick
--   Called on a timer (every 10-15 minutes per Section 5) by the
--   `scheduler-tick` Edge Function. Locks a small due batch of cycles
--   (`FOR UPDATE SKIP LOCKED`, same pattern as claim_outbox_batch —
--   safe even if two invocations somehow overlap), and per cycle:
--
--     question_collection: enqueue an "ending soon" notice a day out;
--       once the close date has passed, nudge the organizer to
--       finalize instead of auto-advancing (see this file's top
--       comment on why automatic selection is out of scope).
--
--     answering: enqueue the two deadline reminders to whoever hasn't
--       submitted yet; once the due date has passed, auto-publish
--       (publish_cycle_internal — identical snapshot logic an
--       organizer's early publish uses) and, if the group's next
--       cycle is due, auto-start it (start_cycle_internal). Both are
--       already idempotent on their own terms (publish is a no-op if
--       already published; start refuses if a cycle is already open),
--       so a retried or overlapping tick can't double-publish or
--       double-start even without the row lock — the lock just avoids
--       redundant work, not incorrect results.
--
--   Every branch ends by recomputing next_action_at for the row it
--   just looked at, so a cycle that only got a reminder (and whose
--   row therefore wasn't otherwise updated, since the recompute
--   trigger only fires on phase/timestamp columns) doesn't get
--   re-selected on the very next tick.
-- ---------------------------------------------------------------------

create function scheduler_tick(p_batch_size int default 50)
returns table (cycles_examined int, emails_enqueued int)
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
  v_group groups%rowtype;
  v_examined int := 0;
  v_before_count bigint;
  v_after_count bigint;
  v_run_id uuid;
begin
  insert into scheduler_runs (started_at) values (now()) returning id into v_run_id;
  select count(*) into v_before_count from email_outbox;

  for v_cycle in
    select * from cycles
    where next_action_at is not null and next_action_at <= now()
    order by next_action_at
    limit p_batch_size
    for update skip locked
  loop
    v_examined := v_examined + 1;
    select * into v_group from groups where id = v_cycle.group_id;

    if v_cycle.phase = 'question_collection' then
      if v_cycle.question_closes_at is not null
         and v_cycle.question_closes_at - interval '1 day' <= now()
         and v_cycle.question_closes_at > now() then
        perform enqueue_group_email(
          v_cycle.group_id, v_cycle.id, 'question_collection_ending_soon',
          jsonb_build_object(
            'group_name', v_group.name, 'cycle_id', v_cycle.id,
            'question_closes_at', v_cycle.question_closes_at
          ),
          'announcements'
        );
      end if;

      if v_cycle.question_closes_at is not null and v_cycle.question_closes_at <= now() then
        perform enqueue_organizer_email(
          v_cycle.group_id, v_cycle.id, 'question_phase_overdue',
          jsonb_build_object(
            'group_name', v_group.name, 'cycle_id', v_cycle.id,
            'question_closes_at', v_cycle.question_closes_at
          ),
          'transactional',
          to_char(now(), 'YYYY-MM-DD') -- at most one nudge per calendar day
        );
      end if;

    elsif v_cycle.phase = 'answering' then
      if v_cycle.answer_due_at is not null
         and v_cycle.answer_due_at - interval '2 days' <= now()
         and v_cycle.answer_due_at > now() then
        perform enqueue_unsubmitted_member_email(
          v_cycle.id, v_cycle.group_id, 'answer_deadline_reminder',
          jsonb_build_object(
            'group_name', v_group.name, 'cycle_id', v_cycle.id, 'answer_due_at', v_cycle.answer_due_at
          )
        );
      end if;

      if v_cycle.answer_due_at is not null
         and v_cycle.answer_due_at - interval '12 hours' <= now()
         and v_cycle.answer_due_at > now() then
        perform enqueue_unsubmitted_member_email(
          v_cycle.id, v_cycle.group_id, 'answer_final_reminder',
          jsonb_build_object(
            'group_name', v_group.name, 'cycle_id', v_cycle.id, 'answer_due_at', v_cycle.answer_due_at
          )
        );
      end if;

      if v_cycle.answer_due_at is not null and v_cycle.answer_due_at <= now() then
        perform publish_cycle_internal(v_cycle.id, null);

        if v_group.next_cycle_at is null or v_group.next_cycle_at <= now() then
          perform start_cycle_internal(v_cycle.group_id, null);
          update groups
          set next_cycle_at = now() + make_interval(days => v_group.interval_days)
          where id = v_group.id;
        end if;
      end if;
    end if;

    update cycles set next_action_at = compute_cycle_next_action_at(cycles.*)
    where id = v_cycle.id;
  end loop;

  select count(*) into v_after_count from email_outbox;

  update scheduler_runs
  set completed_at = now(),
      cycles_examined = v_examined,
      emails_enqueued = greatest((v_after_count - v_before_count)::int, 0)
  where id = v_run_id;

  return query select v_examined, greatest((v_after_count - v_before_count)::int, 0);
exception
  when others then
    update scheduler_runs set completed_at = now(), error = sqlerrm where id = v_run_id;
    raise;
end;
$$;

revoke execute on function scheduler_tick(int) from public;
grant execute on function scheduler_tick(int) to service_role;
