-- Phase 3: complete manual cycle
--
-- Design notes (see implementation_plan.md Sections 4 and 5):
--   * Edge Function infrastructure still doesn't exist yet (it arrives
--     with email in Phase 4 — see the note at the top of
--     0002_groups_memberships_invitations.sql). Every privileged or
--     multi-step operation here (finalizing questions, submitting
--     answers, publishing) is again a SECURITY DEFINER Postgres
--     function callable via `.rpc()`, for the same reasons: one
--     auditable, transactional code path per state change, idempotent
--     where retries are expected.
--   * The cycle state machine is question_collection -> answering ->
--     published, with a `skipped` escape hatch from either open phase.
--     Only the functions below move a cycle between phases; there is
--     no client-writable `phase` column.
--   * `answers` rows are pre-created (empty) for every active member
--     against every finalized question, inside finalize_questions().
--     This means the answer editor's autosave is always a plain
--     UPDATE under RLS — no insert-or-update race, no INSERT policy
--     needed, and the organizer's progress view has a stable
--     denominator (every member has exactly one row per question).
--   * `issue_entries` is a separate table from `answers`, deliberately:
--     it is the frozen, published snapshot ("unaffected by later draft
--     edits" per the plan). Publishing copies submitted answers into
--     it once; a member's answer table row can't be edited afterward
--     anyway (RLS below only allows edits while phase = 'answering'),
--     but keeping them as separate tables also means a bug in future
--     answer-editing code can never retroactively alter a published
--     issue.
--   * Scheduling (`next_action_at`, the scheduler-tick cron job,
--     automatic phase advancement) is Phase 4. All transitions here
--     are organizer-triggered. `next_action_at` is still added now,
--     per the plan's list of per-cycle persisted timestamps, so Phase
--     4 doesn't need another schema change — it's unused (always
--     null) until then.

create type cycle_phase as enum (
  'question_collection',
  'answering',
  'published',
  'skipped'
);

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table cycles (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups (id) on delete cascade,
  sequence_no int not null check (sequence_no > 0),
  phase cycle_phase not null default 'question_collection',
  question_opens_at timestamptz not null default now(),
  question_closes_at timestamptz,
  answer_opens_at timestamptz,
  answer_due_at timestamptz,
  published_at timestamptz,
  next_action_at timestamptz, -- unused until Phase 4's scheduler
  created_by uuid not null references profiles (user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (group_id, sequence_no)
);

-- A group can have at most one cycle that isn't published/skipped at a
-- time — this is the real enforcement of "one edition of the workflow
-- open at once"; start_cycle() also checks it up front for a friendlier
-- error, but this index is what makes it airtight under concurrency.
create unique index cycles_one_open_per_group_uidx
  on cycles (group_id) where phase in ('question_collection', 'answering');

create index cycles_by_group_idx on cycles (group_id, sequence_no desc);
create index cycles_due_idx on cycles (phase, answer_due_at);

create table question_proposals (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references cycles (id) on delete cascade,
  author_id uuid not null references profiles (user_id),
  text text not null check (char_length(btrim(text)) between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index question_proposals_by_cycle_idx on question_proposals (cycle_id);
create index question_proposals_by_author_idx on question_proposals (cycle_id, author_id);

-- Immutable, ordered questions a cycle is actually answered against.
-- `proposal_id` is kept for provenance but the text is copied at
-- finalization time (see finalize_questions()) so a later edit or
-- deletion of the source proposal can never change what members are
-- answering mid-cycle.
create table cycle_questions (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references cycles (id) on delete cascade,
  proposal_id uuid references question_proposals (id) on delete set null,
  text text not null check (char_length(btrim(text)) between 1 and 500),
  position int not null check (position >= 0),
  created_at timestamptz not null default now(),
  unique (cycle_id, position)
);

create index cycle_questions_by_cycle_idx on cycle_questions (cycle_id, position);

create table answers (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references cycle_questions (id) on delete cascade,
  author_id uuid not null references profiles (user_id),
  body text not null default '' check (char_length(body) <= 20000),
  revision int not null default 0,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (question_id, author_id)
);

create index answers_by_author_idx on answers (author_id);

-- The frozen, published record. See the design-notes comment above for
-- why this is a separate table from `answers` rather than a status flag.
create table issue_entries (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references cycles (id) on delete cascade,
  question_id uuid not null references cycle_questions (id) on delete cascade,
  author_id uuid not null references profiles (user_id),
  body text not null,
  answer_revision int not null,
  is_late boolean not null default false,
  published_at timestamptz not null default now(),
  unique (question_id, author_id)
);

create index issue_entries_by_cycle_idx on issue_entries (cycle_id);

alter table cycles enable row level security;
alter table question_proposals enable row level security;
alter table cycle_questions enable row level security;
alter table answers enable row level security;
alter table issue_entries enable row level security;

-- ---------------------------------------------------------------------
-- Authorization helpers (see 0002's is_group_member/is_group_organizer
-- for why these are SECURITY DEFINER: it stops a policy on table X
-- that queries X's parent from re-triggering RLS in a way that could
-- recurse or leak).
-- ---------------------------------------------------------------------

create function is_cycle_member(p_cycle_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from cycles c
    where c.id = p_cycle_id and is_group_member(c.group_id, p_user_id)
  );
$$;

create function is_cycle_organizer(p_cycle_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from cycles c
    where c.id = p_cycle_id and is_group_organizer(c.group_id, p_user_id)
  );
$$;

-- ---------------------------------------------------------------------
-- Identity-immutability triggers (WITH CHECK alone can't compare
-- against the pre-update row — see groups_prevent_identity_change in
-- 0002 for the same pattern).
-- ---------------------------------------------------------------------

create function prevent_proposal_identity_change()
returns trigger
language plpgsql
as $$
begin
  if new.author_id <> old.author_id then
    raise exception 'question_proposals.author_id is immutable';
  end if;
  if new.cycle_id <> old.cycle_id then
    raise exception 'question_proposals.cycle_id is immutable';
  end if;
  return new;
end;
$$;

create trigger question_proposals_prevent_identity_change
  before update on question_proposals
  for each row execute procedure prevent_proposal_identity_change();

create trigger question_proposals_set_updated_at
  before update on question_proposals
  for each row execute procedure set_updated_at();

create function prevent_answer_identity_change()
returns trigger
language plpgsql
as $$
begin
  if new.author_id <> old.author_id then
    raise exception 'answers.author_id is immutable';
  end if;
  if new.question_id <> old.question_id then
    raise exception 'answers.question_id is immutable';
  end if;
  return new;
end;
$$;

create trigger answers_prevent_identity_change
  before update on answers
  for each row execute procedure prevent_answer_identity_change();

-- Bump the revision counter whenever the body actually changes, so a
-- published issue_entries row (which snapshots `answer_revision`) can
-- always be traced back to the exact draft state it came from.
create function bump_answer_revision()
returns trigger
language plpgsql
as $$
begin
  if new.body is distinct from old.body then
    new.revision = old.revision + 1;
  end if;
  return new;
end;
$$;

create trigger answers_bump_revision
  before update on answers
  for each row execute procedure bump_answer_revision();

create trigger answers_set_updated_at
  before update on answers
  for each row execute procedure set_updated_at();

create trigger cycles_set_updated_at
  before update on cycles
  for each row execute procedure set_updated_at();

-- ---------------------------------------------------------------------
-- cycles policies (select only — every write is a state-machine
-- transition and goes through a function below)
-- ---------------------------------------------------------------------

create policy "cycles_select_member"
  on cycles for select
  using (is_group_member(group_id, auth.uid()));

-- ---------------------------------------------------------------------
-- question_proposals policies
--   Any active member can read every proposal for a cycle in their
--   group (so people don't duplicate each other's suggestions, and so
--   the organizer can see the full pool to pick from). Writes are
--   direct RLS, not functions — unlike the state-machine transitions
--   below, "add/edit/remove my own suggestion" has no side effects to
--   keep atomic beyond the phase check itself, so a table policy is
--   enough (the same reasoning 0002 used for groups_update_organizer).
-- ---------------------------------------------------------------------

create policy "question_proposals_select_member"
  on question_proposals for select
  using (is_cycle_member(cycle_id, auth.uid()));

create policy "question_proposals_insert_own"
  on question_proposals for insert
  with check (
    author_id = auth.uid()
    and is_cycle_member(cycle_id, auth.uid())
    and exists (
      select 1 from cycles c
      where c.id = question_proposals.cycle_id and c.phase = 'question_collection'
    )
  );

create policy "question_proposals_update_own"
  on question_proposals for update
  using (
    author_id = auth.uid()
    and exists (
      select 1 from cycles c
      where c.id = question_proposals.cycle_id and c.phase = 'question_collection'
    )
  )
  with check (author_id = auth.uid());

create policy "question_proposals_delete_own"
  on question_proposals for delete
  using (
    author_id = auth.uid()
    and exists (
      select 1 from cycles c
      where c.id = question_proposals.cycle_id and c.phase = 'question_collection'
    )
  );

-- ---------------------------------------------------------------------
-- cycle_questions policies (select only — written exclusively by
-- finalize_questions())
-- ---------------------------------------------------------------------

create policy "cycle_questions_select_member"
  on cycle_questions for select
  using (is_cycle_member(cycle_id, auth.uid()));

-- ---------------------------------------------------------------------
-- answers policies
--   Select is deliberately author-only: this is the enforcement of
--   "members cannot read another person's draft or submitted answer
--   before publication" (plan Section 4). The organizer's progress
--   view (get_cycle_progress() below) is a SECURITY DEFINER function
--   that returns completion booleans/counts, never `body`, precisely
--   so an organizer can see who's done without this policy needing to
--   grant them row access.
--   Update is allowed directly (no function) once a row exists, which
--   it always does — finalize_questions() pre-creates one empty answers
--   row per active member per question. Submitting, reopening, and the
--   late/post-publish path all go through functions because those do
--   have side effects (an issue_entries snapshot, an audit event) that
--   need to happen atomically with the state change.
-- ---------------------------------------------------------------------

create policy "answers_select_own"
  on answers for select
  using (author_id = auth.uid());

create policy "answers_update_own_draft"
  on answers for update
  using (
    author_id = auth.uid()
    and submitted_at is null
    and exists (
      select 1 from cycle_questions cq
      join cycles c on c.id = cq.cycle_id
      where cq.id = answers.question_id and c.phase = 'answering'
    )
  )
  with check (author_id = auth.uid());

-- ---------------------------------------------------------------------
-- issue_entries policies (select only, published cycles only — written
-- exclusively by publish_cycle() and submit_late_answer())
-- ---------------------------------------------------------------------

create policy "issue_entries_select_member"
  on issue_entries for select
  using (
    exists (
      select 1 from cycles c
      where c.id = issue_entries.cycle_id
        and c.phase = 'published'
        and is_group_member(c.group_id, auth.uid())
    )
  );

-- ---------------------------------------------------------------------
-- RPC: start_cycle
--   Organizer-only. Opens a new cycle's question-collection phase.
--   The partial unique index above is the hard backstop against two
--   concurrent calls both succeeding; the exists() check just gives a
--   friendlier error in the common (non-racing) case.
-- ---------------------------------------------------------------------

create function start_cycle(p_group_id uuid)
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_group groups%rowtype;
  v_cycle cycles%rowtype;
  v_next_seq int;
begin
  if not is_group_organizer(p_group_id, auth.uid()) then
    raise exception 'Only an organizer can start a cycle.' using errcode = '42501';
  end if;

  if exists (
    select 1 from cycles
    where group_id = p_group_id and phase in ('question_collection', 'answering')
  ) then
    raise exception 'This group already has an open cycle.' using errcode = '22023';
  end if;

  select * into v_group from groups where id = p_group_id;

  select coalesce(max(sequence_no), 0) + 1 into v_next_seq
  from cycles where group_id = p_group_id;

  insert into cycles (
    group_id, sequence_no, phase, question_opens_at, question_closes_at, created_by
  )
  values (
    p_group_id, v_next_seq, 'question_collection', now(),
    now() + make_interval(days => v_group.question_phase_days), auth.uid()
  )
  returning * into v_cycle;

  perform log_audit_event(
    p_group_id, auth.uid(), 'cycle_started',
    jsonb_build_object('cycle_id', v_cycle.id, 'sequence_no', v_next_seq)
  );

  return v_cycle;
exception
  when unique_violation then
    raise exception 'This group already has an open cycle.' using errcode = '22023';
end;
$$;

grant execute on function start_cycle(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: finalize_questions
--   Organizer-only. Locks in an ordered set of questions (drawn from
--   this cycle's proposals), closes the question phase, opens
--   answering, and pre-creates one empty draft answer row per active
--   member per question (see the design-notes comment at the top of
--   this file for why).
-- ---------------------------------------------------------------------

create function finalize_questions(p_cycle_id uuid, p_proposal_ids uuid[])
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

  return v_cycle;
end;
$$;

grant execute on function finalize_questions(uuid, uuid[]) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: submit_answers
--   Member-only, own answers. Requires every question in the cycle to
--   have a non-empty draft, then atomically marks them all submitted.
--   Idempotent: a retried call after a network timeout finds nothing
--   left to update (the `submitted_at is null` clause) and skips the
--   audit event rather than logging a duplicate.
-- ---------------------------------------------------------------------

create function submit_answers(p_cycle_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
  v_unanswered int;
  v_updated int;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in.' using errcode = '28000';
  end if;

  select * into v_cycle from cycles where id = p_cycle_id;
  if v_cycle.id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
  end if;

  if not is_group_member(v_cycle.group_id, auth.uid()) then
    raise exception 'You are not a member of this group.' using errcode = '42501';
  end if;

  if v_cycle.phase <> 'answering' then
    raise exception 'Answers can only be submitted while the cycle is open for answering.'
      using errcode = '22023';
  end if;

  select count(*) into v_unanswered
  from answers a
  join cycle_questions cq on cq.id = a.question_id
  where cq.cycle_id = p_cycle_id
    and a.author_id = auth.uid()
    and btrim(a.body) = '';

  if v_unanswered > 0 then
    raise exception 'Answer every question before submitting.' using errcode = '22023';
  end if;

  update answers a
  set submitted_at = now()
  from cycle_questions cq
  where cq.id = a.question_id
    and cq.cycle_id = p_cycle_id
    and a.author_id = auth.uid()
    and a.submitted_at is null;

  get diagnostics v_updated = row_count;

  if v_updated > 0 then
    perform log_audit_event(
      v_cycle.group_id, auth.uid(), 'answers_submitted',
      jsonb_build_object('cycle_id', p_cycle_id)
    );
  end if;
end;
$$;

grant execute on function submit_answers(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: reopen_submission
--   Organizer-only. Lets one member revise already-submitted answers
--   before the cycle publishes.
-- ---------------------------------------------------------------------

create function reopen_submission(p_cycle_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
begin
  select * into v_cycle from cycles where id = p_cycle_id;
  if v_cycle.id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
  end if;

  if not is_group_organizer(v_cycle.group_id, auth.uid()) then
    raise exception 'Only an organizer can reopen a submission.' using errcode = '42501';
  end if;

  if v_cycle.phase <> 'answering' then
    raise exception 'Submissions can only be reopened while the cycle is open for answering.'
      using errcode = '22023';
  end if;

  update answers a
  set submitted_at = null
  from cycle_questions cq
  where cq.id = a.question_id
    and cq.cycle_id = p_cycle_id
    and a.author_id = p_user_id;

  perform log_audit_event(
    v_cycle.group_id, auth.uid(), 'submission_reopened',
    jsonb_build_object('cycle_id', p_cycle_id, 'user_id', p_user_id)
  );
end;
$$;

grant execute on function reopen_submission(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: change_cycle_deadline
--   Organizer-only. Extends (or shortens) whichever deadline the
--   cycle's current phase is waiting on.
-- ---------------------------------------------------------------------

create function change_cycle_deadline(p_cycle_id uuid, p_new_due_at timestamptz)
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
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

  perform log_audit_event(
    v_cycle.group_id, auth.uid(), 'cycle_deadline_changed',
    jsonb_build_object('cycle_id', p_cycle_id, 'phase', v_cycle.phase, 'new_due_at', p_new_due_at)
  );

  return v_cycle;
end;
$$;

grant execute on function change_cycle_deadline(uuid, timestamptz) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: publish_cycle
--   Organizer-only. Snapshots every submitted answer into
--   issue_entries and moves the cycle to 'published'. Idempotent: if
--   the cycle is already published, this is a no-op that returns the
--   current row rather than erroring, so a retried call after a
--   client-side timeout can't double-publish or raise confusingly.
-- ---------------------------------------------------------------------

create function publish_cycle(p_cycle_id uuid)
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
  v_entries int;
begin
  select * into v_cycle from cycles where id = p_cycle_id for update;
  if v_cycle.id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
  end if;

  if not is_group_organizer(v_cycle.group_id, auth.uid()) then
    raise exception 'Only an organizer can publish a cycle.' using errcode = '42501';
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

  perform log_audit_event(
    v_cycle.group_id, auth.uid(), 'cycle_published',
    jsonb_build_object('cycle_id', p_cycle_id, 'entry_count', v_entries)
  );

  return v_cycle;
end;
$$;

grant execute on function publish_cycle(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: submit_late_answer
--   Member-only, own answer, cycle already published. Updates the
--   member's answer row and adds/updates a corresponding issue_entries
--   row labeled `is_late`, matching the plan's "late answers may be
--   added after publication and are labeled 'added later'".
-- ---------------------------------------------------------------------

create function submit_late_answer(p_question_id uuid, p_body text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
  v_body text := btrim(p_body);
  v_updated int;
  v_revision int;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in.' using errcode = '28000';
  end if;

  select c.* into v_cycle
  from cycle_questions cq
  join cycles c on c.id = cq.cycle_id
  where cq.id = p_question_id;

  if v_cycle.id is null then
    raise exception 'Question not found.' using errcode = 'P0002';
  end if;

  if not is_group_member(v_cycle.group_id, auth.uid()) then
    raise exception 'You are not a member of this group.' using errcode = '42501';
  end if;

  if v_cycle.phase <> 'published' then
    raise exception 'This is for adding an answer after a cycle has already published — answer normally before then.'
      using errcode = '22023';
  end if;

  if v_body = '' then
    raise exception 'Enter an answer before submitting.' using errcode = '22023';
  end if;

  if char_length(v_body) > 20000 then
    raise exception 'Answer is too long.' using errcode = '22023';
  end if;

  update answers
  set body = v_body, submitted_at = now()
  where question_id = p_question_id and author_id = auth.uid();

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'No draft answer found for this question.' using errcode = 'P0002';
  end if;

  select revision into v_revision
  from answers where question_id = p_question_id and author_id = auth.uid();

  insert into issue_entries (cycle_id, question_id, author_id, body, answer_revision, is_late, published_at)
  values (v_cycle.id, p_question_id, auth.uid(), v_body, v_revision, true, now())
  on conflict (question_id, author_id) do update
    set body = excluded.body, answer_revision = excluded.answer_revision, is_late = true;

  perform log_audit_event(
    v_cycle.group_id, auth.uid(), 'late_answer_added',
    jsonb_build_object('cycle_id', v_cycle.id, 'question_id', p_question_id)
  );
end;
$$;

grant execute on function submit_late_answer(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: skip_cycle
--   Organizer-only. Abandons an open cycle without publishing it.
-- ---------------------------------------------------------------------

create function skip_cycle(p_cycle_id uuid)
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
begin
  select * into v_cycle from cycles where id = p_cycle_id for update;
  if v_cycle.id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
  end if;

  if not is_group_organizer(v_cycle.group_id, auth.uid()) then
    raise exception 'Only an organizer can skip a cycle.' using errcode = '42501';
  end if;

  if v_cycle.phase not in ('question_collection', 'answering') then
    raise exception 'Only an open cycle can be skipped.' using errcode = '22023';
  end if;

  update cycles set phase = 'skipped' where id = p_cycle_id returning * into v_cycle;

  perform log_audit_event(
    v_cycle.group_id, auth.uid(), 'cycle_skipped',
    jsonb_build_object('cycle_id', p_cycle_id)
  );

  return v_cycle;
end;
$$;

grant execute on function skip_cycle(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: get_cycle_progress
--   Organizer-only. Per-member completion counts and a submitted
--   boolean — deliberately never `body`. This is how the organizer
--   progress screen satisfies "see completion status (but not private
--   draft text)" without needing a SELECT policy on `answers` that
--   would expose other members' rows.
-- ---------------------------------------------------------------------

create function get_cycle_progress(p_cycle_id uuid)
returns table (
  user_id uuid,
  display_name text,
  questions_total int,
  questions_answered int,
  submitted boolean,
  submitted_at timestamptz
)
language plpgsql
stable
security definer set search_path = public
as $$
declare
  v_group_id uuid;
  v_question_count int;
begin
  select group_id into v_group_id from cycles where id = p_cycle_id;
  if v_group_id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
  end if;

  if not is_group_organizer(v_group_id, auth.uid()) then
    raise exception 'Only an organizer can view cycle progress.' using errcode = '42501';
  end if;

  select count(*) into v_question_count from cycle_questions where cycle_id = p_cycle_id;

  return query
  select
    m.user_id,
    coalesce(nullif(p.display_name, ''), '(no name set)') as display_name,
    v_question_count as questions_total,
    count(a.id) filter (where btrim(a.body) <> '')::int as questions_answered,
    (v_question_count > 0
      and count(a.id) filter (where a.submitted_at is not null) = v_question_count) as submitted,
    max(a.submitted_at) as submitted_at
  from memberships m
  join profiles p on p.user_id = m.user_id
  left join answers a
    on a.author_id = m.user_id
    and a.question_id in (select id from cycle_questions where cycle_id = p_cycle_id)
  where m.group_id = v_group_id and m.status = 'active'
  group by m.user_id, p.display_name
  order by p.display_name;
end;
$$;

grant execute on function get_cycle_progress(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Table grants (RLS policies decide *which rows*; these decide whether
-- the role can attempt the operation at all — see the equivalent
-- comment block at the bottom of 0002_groups_memberships_invitations.sql).
-- ---------------------------------------------------------------------

grant select on cycles, cycle_questions, issue_entries to authenticated;
grant select, insert, update, delete on question_proposals to authenticated;
grant select, update on answers to authenticated;

grant select on cycles, question_proposals, cycle_questions, answers, issue_entries to anon;
