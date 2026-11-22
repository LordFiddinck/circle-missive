-- 0010: organizers can stop two members from seeing each other's answers.
--
-- A block is a symmetric pair within one group: neither person can read
-- the other's entries in published issues. Everything else is
-- unchanged, and each of the two still sees everyone else's answers
-- and their own.
--
-- Where this is enforced: `issue_entries` is the only table through
-- which one member can read another's answer (`answers` is author-only,
-- emails carry no answer text, and the organizer progress view returns
-- counts, never bodies). So the rule lives in that table's row-level
-- security policy, which means it holds for the UI, the API, and any
-- future feature that reads entries.
--
-- Design notes:
--   * Retroactive both ways: RLS is evaluated at query time, so hiding
--     a pair also hides issues already published, and restoring them
--     brings those back.
--   * Blocks survive a member leaving or being removed, so a returning
--     member is still blocked.
--   * The blocked people are not told. Only organizers can read the
--     block list; members can neither read nor write it.
--   * The policy must NOT query `answer_visibility_blocks` directly. That
--     table is organizer-only under RLS, so for an ordinary member the
--     subquery would see zero rows and silently let everything through.
--     The lookup goes through a SECURITY DEFINER function instead.

create table answer_visibility_blocks (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups (id) on delete cascade,
  -- Stored in canonical order (user_a < user_b) so a pair has exactly
  -- one row no matter which order the organizer picked them in.
  user_a uuid not null references profiles (user_id) on delete cascade,
  user_b uuid not null references profiles (user_id) on delete cascade,
  created_by uuid references profiles (user_id) on delete set null,
  created_at timestamptz not null default now(),
  constraint answer_visibility_blocks_ordered check (user_a < user_b),
  constraint answer_visibility_blocks_unique unique (group_id, user_a, user_b)
);

alter table answer_visibility_blocks enable row level security;

create policy "answer_visibility_blocks_select_organizer"
  on answer_visibility_blocks for select
  using (is_group_organizer(group_id, auth.uid()));

-- No insert/update/delete policies: writes go through the two functions
-- below. Supabase grants new tables to anon/authenticated by default,
-- so revoke explicitly rather than rely on RLS alone.
revoke all on answer_visibility_blocks from public, anon, authenticated;
grant select on answer_visibility_blocks to authenticated;

-- Is the signed-in user blocked from reading p_author_id's answers in
-- this group? Callable by anyone (RLS policies run it as the invoker);
-- it only ever answers about the caller's own blocks.
create function is_answer_hidden_from_me(p_group_id uuid, p_author_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from answer_visibility_blocks b
      where b.group_id = p_group_id
        and b.user_a = least(auth.uid(), p_author_id)
        and b.user_b = greatest(auth.uid(), p_author_id)
    );
$$;

drop policy "issue_entries_select_member" on issue_entries;

create policy "issue_entries_select_member"
  on issue_entries for select
  using (
    exists (
      select 1 from cycles c
      where c.id = issue_entries.cycle_id
        and c.phase = 'published'
        and is_group_member(c.group_id, auth.uid())
        and not is_answer_hidden_from_me(c.group_id, issue_entries.author_id)
    )
  );

-- ---------------------------------------------------------------------
-- Organizer actions
-- ---------------------------------------------------------------------

create function hide_answers_between(
  p_group_id uuid,
  p_user_one uuid,
  p_user_two uuid
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_a uuid := least(p_user_one, p_user_two);
  v_b uuid := greatest(p_user_one, p_user_two);
  v_inserted int;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in.' using errcode = '28000';
  end if;

  if not is_group_organizer(p_group_id, auth.uid()) then
    raise exception 'Only an organizer can hide answers between members.'
      using errcode = '42501';
  end if;

  if p_user_one is null or p_user_two is null or p_user_one = p_user_two then
    raise exception 'Choose two different people.' using errcode = '22023';
  end if;

  if not (is_group_member(p_group_id, p_user_one) and is_group_member(p_group_id, p_user_two)) then
    raise exception 'Both people must be active members of this group.'
      using errcode = '22023';
  end if;

  insert into answer_visibility_blocks (group_id, user_a, user_b, created_by)
  values (p_group_id, v_a, v_b, auth.uid())
  on conflict (group_id, user_a, user_b) do nothing;

  get diagnostics v_inserted = row_count;

  -- Idempotent: repeating the same request neither errors nor logs again.
  if v_inserted > 0 then
    perform log_audit_event(
      p_group_id, auth.uid(), 'answer_visibility_hidden',
      jsonb_build_object('user_a', v_a, 'user_b', v_b)
    );
  end if;
end;
$$;

create function restore_answers_between(
  p_group_id uuid,
  p_user_one uuid,
  p_user_two uuid
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_a uuid := least(p_user_one, p_user_two);
  v_b uuid := greatest(p_user_one, p_user_two);
  v_deleted int;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in.' using errcode = '28000';
  end if;

  if not is_group_organizer(p_group_id, auth.uid()) then
    raise exception 'Only an organizer can restore answer visibility.'
      using errcode = '42501';
  end if;

  delete from answer_visibility_blocks
  where group_id = p_group_id and user_a = v_a and user_b = v_b;

  get diagnostics v_deleted = row_count;

  if v_deleted > 0 then
    perform log_audit_event(
      p_group_id, auth.uid(), 'answer_visibility_restored',
      jsonb_build_object('user_a', v_a, 'user_b', v_b)
    );
  end if;
end;
$$;

grant execute on function hide_answers_between(uuid, uuid, uuid) to authenticated;
grant execute on function restore_answers_between(uuid, uuid, uuid) to authenticated;
