-- 0009: question attribution, manual question release, partial
-- submissions, and automatic submission of saved drafts at cycle end.
--
-- What changed and why:
--
--   1. Attribution. A member who suggests a question now chooses
--      whether their name is shown on it (`question_proposals.show_author`,
--      default true). When the organizer finalizes/releases questions,
--      that choice is frozen into `cycle_questions.asked_by` (the
--      author's id if they opted to be shown, NULL if not), so the
--      answering screen and the published issue can show "Asked by X"
--      without ever exposing an author who asked to stay anonymous.
--
--   2. Manual release. `release_questions()` opens answering with every
--      suggestion, in the order suggested, in one call. It is an
--      alternative to hand-picking via finalize_questions(). Both now
--      share `finalize_questions_internal()`, which the scheduler also
--      uses: when a cycle's question phase ends and at least one
--      question has been suggested, the scheduler now releases them
--      itself (previously it only nudged the organizer). With no
--      suggestions it still just nudges.
--
--   3. Partial submissions. `submit_answers()` no longer demands every
--      question be answered; it needs at least one. Blank questions are
--      simply left out of the published issue (a member can still add
--      them afterwards through submit_late_answer()).
--
--   4. Auto-submit at cycle end. `publish_cycle_internal()` (used by
--      both the scheduler's on-time publish and an organizer's manual
--      publish) first submits the saved drafts of any active member who
--      has written at least one answer but never pressed Submit.

-- ---------------------------------------------------------------------
-- 1. Attribution columns
-- ---------------------------------------------------------------------

alter table question_proposals
  add column show_author boolean not null default true;

alter table cycle_questions
  add column asked_by uuid references profiles (user_id) on delete set null;

-- Questions finalized before this migration were already shown with
-- their author in the suggestion list, and every existing proposal now
-- has show_author = true, so carry that attribution over.
update cycle_questions cq
set asked_by = qp.author_id
from question_proposals qp
where qp.id = cq.proposal_id and qp.show_author;

-- ---------------------------------------------------------------------
-- 2. finalize_questions_internal / finalize_questions / release_questions
--    The body is 0004's finalize_questions(), minus the caller check
--    (callers do their own), plus asked_by. p_actor_id = null means
--    "the scheduler did this".
-- ---------------------------------------------------------------------

create function finalize_questions_internal(
  p_cycle_id uuid,
  p_proposal_ids uuid[],
  p_actor_id uuid
)
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
  v_asked_by uuid;
  v_member record;
  v_distinct_count int;
begin
  select * into v_cycle from cycles where id = p_cycle_id for update;
  if v_cycle.id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
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
    v_text := null;
    v_asked_by := null;

    select text, case when show_author then author_id else null end
      into v_text, v_asked_by
    from question_proposals
    where id = v_proposal_id and cycle_id = p_cycle_id;

    if v_text is null then
      raise exception 'One of the selected questions does not belong to this cycle.'
        using errcode = '22023';
    end if;

    insert into cycle_questions (cycle_id, proposal_id, text, position, asked_by)
    values (p_cycle_id, v_proposal_id, v_text, v_position, v_asked_by);

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
    v_cycle.group_id, p_actor_id,
    case when p_actor_id is null then 'questions_auto_finalized' else 'questions_finalized' end,
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

revoke execute on function finalize_questions_internal(uuid, uuid[], uuid)
  from public, anon, authenticated;
grant execute on function finalize_questions_internal(uuid, uuid[], uuid) to service_role;

-- Same signature and error messages as 0004's version; now a thin
-- wrapper so there is one code path.
create or replace function finalize_questions(p_cycle_id uuid, p_proposal_ids uuid[])
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_group_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in.' using errcode = '28000';
  end if;

  select group_id into v_group_id from cycles where id = p_cycle_id;
  if v_group_id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
  end if;

  if not is_group_organizer(v_group_id, auth.uid()) then
    raise exception 'Only an organizer can finalize questions.' using errcode = '42501';
  end if;

  return finalize_questions_internal(p_cycle_id, p_proposal_ids, auth.uid());
end;
$$;

grant execute on function finalize_questions(uuid, uuid[]) to authenticated;

-- One-click manual release: every suggestion, in the order suggested.
create function release_questions(p_cycle_id uuid)
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_group_id uuid;
  v_ids uuid[];
begin
  if auth.uid() is null then
    raise exception 'Must be signed in.' using errcode = '28000';
  end if;

  select group_id into v_group_id from cycles where id = p_cycle_id;
  if v_group_id is null then
    raise exception 'Cycle not found.' using errcode = 'P0002';
  end if;

  if not is_group_organizer(v_group_id, auth.uid()) then
    raise exception 'Only an organizer can release questions.' using errcode = '42501';
  end if;

  select array_agg(id order by created_at, id) into v_ids
  from question_proposals where cycle_id = p_cycle_id;

  if v_ids is null then
    raise exception 'No questions have been suggested yet.' using errcode = '22023';
  end if;

  return finalize_questions_internal(p_cycle_id, v_ids, auth.uid());
end;
$$;

grant execute on function release_questions(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. submit_answers: partial submissions allowed
-- ---------------------------------------------------------------------

create or replace function submit_answers(p_cycle_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
  v_answered int;
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

  select count(*) into v_answered
  from answers a
  join cycle_questions cq on cq.id = a.question_id
  where cq.cycle_id = p_cycle_id
    and a.author_id = auth.uid()
    and btrim(a.body) <> '';

  if v_answered = 0 then
    raise exception 'Answer at least one question before submitting.' using errcode = '22023';
  end if;

  -- Every row is marked submitted, blanks included: a submission is
  -- one atomic act (and the organizer's reopen_submission() undoes it
  -- as one). Blank answers are left out of the published issue.
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
      jsonb_build_object('cycle_id', p_cycle_id, 'answered_count', v_answered)
    );
  end if;
end;
$$;

grant execute on function submit_answers(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4. publish_cycle_internal: auto-submit saved drafts, skip blanks
--    Body is 0004's, with two additions marked below.
-- ---------------------------------------------------------------------

create or replace function publish_cycle_internal(p_cycle_id uuid, p_actor_id uuid)
returns cycles
language plpgsql
security definer set search_path = public
as $$
declare
  v_cycle cycles%rowtype;
  v_group groups%rowtype;
  v_entries int;
  v_auto_submitted int;
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

  -- ADDITION 1: submit the saved drafts of any active member who wrote
  -- at least one answer but never pressed Submit.
  with submitted as (
    update answers a
    set submitted_at = now()
    from cycle_questions cq
    where cq.id = a.question_id
      and cq.cycle_id = p_cycle_id
      and a.submitted_at is null
      and exists (
        select 1 from memberships m
        where m.group_id = v_cycle.group_id
          and m.user_id = a.author_id
          and m.status = 'active'
      )
      and exists (
        select 1
        from answers a2
        join cycle_questions cq2 on cq2.id = a2.question_id
        where cq2.cycle_id = p_cycle_id
          and a2.author_id = a.author_id
          and btrim(a2.body) <> ''
      )
    returning a.author_id
  )
  select count(distinct author_id) into v_auto_submitted from submitted;

  -- ADDITION 2: `btrim(a.body) <> ''` — a partial submission leaves
  -- blank rows marked submitted; they must not become empty entries.
  insert into issue_entries (cycle_id, question_id, author_id, body, answer_revision, is_late, published_at)
  select cq.cycle_id, a.question_id, a.author_id, a.body, a.revision, false, now()
  from answers a
  join cycle_questions cq on cq.id = a.question_id
  where cq.cycle_id = p_cycle_id
    and a.submitted_at is not null
    and btrim(a.body) <> ''
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
    jsonb_build_object(
      'cycle_id', p_cycle_id,
      'entry_count', v_entries,
      'auto_submitted_members', v_auto_submitted
    )
  );

  perform enqueue_group_email(
    v_cycle.group_id, p_cycle_id, 'issue_published',
    jsonb_build_object('group_name', v_group.name, 'cycle_id', p_cycle_id, 'sequence_no', v_cycle.sequence_no),
    'announcements'
  );

  return v_cycle;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. scheduler_tick: release suggestions automatically once the
--    question phase has ended. Identical to 0004's version except for
--    the overdue branch of question_collection.
--
--    The release runs in its own sub-block so a failure on one cycle
--    (say, more than 50 suggestions) can't abort the whole tick and
--    leave every other group stuck; on failure the organizer is nudged
--    exactly as before. At most 50 suggestions are released, oldest
--    first; the organizer can still hand-pick via finalize_questions()
--    before the deadline.
-- ---------------------------------------------------------------------

create or replace function scheduler_tick(p_batch_size int default 50)
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
  v_ids uuid[];
  v_released boolean;
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
        v_released := false;

        select array_agg(id order by created_at, id) into v_ids
        from (
          select id, created_at from question_proposals
          where cycle_id = v_cycle.id
          order by created_at, id
          limit 50
        ) s;

        if v_ids is not null then
          begin
            perform finalize_questions_internal(v_cycle.id, v_ids, null);
            v_released := true;
          exception
            when others then
              v_released := false;
          end;
        end if;

        if not v_released then
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

revoke execute on function scheduler_tick(int) from public, anon, authenticated;
grant execute on function scheduler_tick(int) to service_role;
