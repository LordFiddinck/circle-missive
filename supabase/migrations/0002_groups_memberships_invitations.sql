-- Phase 2: groups, invites, and authorization
--
-- Design notes (see implementation_plan.md Section 3 and 4):
--   * We don't have Edge Function infrastructure yet (that arrives with
--     email in Phase 4), so every privileged, multi-step operation here
--     (creating an invite, accepting one, removing a member, etc.) is a
--     Postgres SECURITY DEFINER function instead, callable through
--     supabase-js's `.rpc()`. This keeps token generation/hashing,
--     authorization checks, and audit logging server-side and atomic,
--     the same way an Edge Function would, without needing secrets or
--     a deployed function yet.
--   * `memberships` and `invitations` have NO insert/update/delete RLS
--     policies for the `authenticated` role at all. Every mutation goes
--     through one of the functions below, which run as the function
--     owner and therefore bypass RLS after doing their own checks. This
--     is deliberate: it means there is exactly one, auditable code path
--     for "someone joined a group" or "someone was removed", rather than
--     a raw table update that could skip the audit trail.

create extension if not exists pgcrypto;

create type membership_role as enum ('organizer', 'member');
create type membership_status as enum ('active', 'removed', 'left');
-- 'expired' is set by a future housekeeping sweep (Phase 4's
-- scheduler), not by accept_invitation() itself: a PL/pgSQL function
-- can't durably write a status and then raise an exception in the same
-- call, since the exception rolls that write back too. Everywhere in
-- this file, "expired" is therefore judged as
-- (status = 'pending' and expires_at < now()), not solely by the
-- stored enum value.
create type invitation_status as enum ('pending', 'accepted', 'revoked', 'expired');

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 100),
  timezone text not null default 'UTC',
  interval_days int not null default 28 check (interval_days > 0),
  question_phase_days int not null default 7 check (question_phase_days > 0),
  answer_phase_days int not null default 7 check (answer_phase_days > 0),
  next_cycle_at timestamptz,
  created_by uuid not null references profiles (user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table memberships (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups (id) on delete cascade,
  user_id uuid not null references profiles (user_id) on delete cascade,
  role membership_role not null default 'member',
  status membership_status not null default 'active',
  invited_by uuid references profiles (user_id),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  unique (group_id, user_id)
);

create index memberships_active_by_group_idx
  on memberships (group_id) where status = 'active';
create index memberships_active_by_user_idx
  on memberships (user_id) where status = 'active';

create table invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups (id) on delete cascade,
  email_normalized text not null check (email_normalized = lower(btrim(email_normalized))),
  token_hash text not null unique,
  status invitation_status not null default 'pending',
  invited_by uuid not null references profiles (user_id),
  expires_at timestamptz not null,
  accepted_by uuid references profiles (user_id),
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create index invitations_by_group_idx on invitations (group_id);

-- Only one *pending* invite per (group, email) at a time; resending
-- reuses the same row instead of creating duplicates.
create unique index invitations_group_email_pending_uidx
  on invitations (group_id, email_normalized)
  where status = 'pending';

create table audit_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references groups (id) on delete cascade,
  actor_id uuid references profiles (user_id),
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index audit_events_by_group_idx on audit_events (group_id, created_at desc);

alter table groups enable row level security;
alter table memberships enable row level security;
alter table invitations enable row level security;
alter table audit_events enable row level security;

-- ---------------------------------------------------------------------
-- profiles: extend visibility to fellow group members
--
-- Phase 1 scoped `profiles` SELECT to the owner only, anticipating this
-- exact extension point ("profile visibility beyond the owner is
-- scoped through group membership in later migrations" — see
-- 0001_init_profiles.sql). Member lists and invite-preview screens
-- need to show other members' display names.
-- ---------------------------------------------------------------------

create policy "profiles_select_fellow_member"
  on profiles for select
  using (
    exists (
      select 1
      from memberships mine
      join memberships theirs on theirs.group_id = mine.group_id
      where mine.user_id = auth.uid()
        and mine.status = 'active'
        and theirs.user_id = profiles.user_id
        and theirs.status = 'active'
    )
  );

-- ---------------------------------------------------------------------
-- Authorization helpers
--
-- These are SECURITY DEFINER so that policies which reference
-- `memberships` don't recurse into RLS on `memberships` itself (a
-- well-known Postgres RLS trap: a policy on table X that queries X
-- again re-triggers RLS on X). `stable` lets the planner cache/reuse
-- the result within a single statement.
-- ---------------------------------------------------------------------

create function is_group_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from memberships
    where group_id = p_group_id
      and user_id = p_user_id
      and status = 'active'
  );
$$;

create function is_group_organizer(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from memberships
    where group_id = p_group_id
      and user_id = p_user_id
      and role = 'organizer'
      and status = 'active'
  );
$$;

create function log_audit_event(
  p_group_id uuid,
  p_actor_id uuid,
  p_event_type text,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language sql
security definer set search_path = public
as $$
  insert into audit_events (group_id, actor_id, event_type, metadata)
  values (p_group_id, p_actor_id, p_event_type, p_metadata);
$$;

-- ---------------------------------------------------------------------
-- groups policies
-- ---------------------------------------------------------------------

create policy "groups_select_member"
  on groups for select
  using (is_group_member(id, auth.uid()));

-- No insert policy on `groups`: creating a group always goes through
-- create_group() below. This sidesteps a real RLS trap — an
-- `INSERT ... RETURNING` (which supabase-js's `.insert().select()`
-- uses) must satisfy the SELECT policy immediately on the inserted
-- row, but an AFTER INSERT trigger that creates the organizer
-- membership runs too late to satisfy `is_group_member` in time for
-- that same RETURNING clause. Doing both inserts inside one
-- SECURITY DEFINER function (which bypasses RLS as the function
-- owner) avoids the race entirely.

create policy "groups_update_organizer"
  on groups for update
  using (is_group_organizer(id, auth.uid()))
  with check (is_group_organizer(id, auth.uid()));

-- No delete policy: groups are never hard-deleted from the client in
-- the MVP (see implementation plan Section 7, account/data lifecycle).

-- `id` and `created_by` must not change on update. RLS's WITH CHECK only
-- sees the new row, not the old one, so this needs a trigger.
create function prevent_group_identity_change()
returns trigger
language plpgsql
as $$
begin
  if new.id <> old.id then
    raise exception 'groups.id is immutable';
  end if;
  if new.created_by <> old.created_by then
    raise exception 'groups.created_by is immutable';
  end if;
  return new;
end;
$$;

create trigger groups_prevent_identity_change
  before update on groups
  for each row execute procedure prevent_group_identity_change();

create trigger groups_set_updated_at
  before update on groups
  for each row execute procedure set_updated_at();

-- Creating a group and making its creator an active organizer happen
-- together, atomically, as the function owner (see the comment above
-- the removed groups insert policy for why this isn't a trigger).
create function create_group(
  p_name text,
  p_timezone text default 'UTC',
  p_interval_days int default 28,
  p_question_phase_days int default 7,
  p_answer_phase_days int default 7
)
returns groups
language plpgsql
security definer set search_path = public
as $$
declare
  v_group groups%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in to create a group.' using errcode = '28000';
  end if;

  insert into groups (
    name, timezone, interval_days, question_phase_days, answer_phase_days, created_by
  )
  values (
    btrim(p_name), p_timezone, p_interval_days, p_question_phase_days, p_answer_phase_days, auth.uid()
  )
  returning * into v_group;

  insert into memberships (group_id, user_id, role, status)
  values (v_group.id, auth.uid(), 'organizer', 'active');

  perform log_audit_event(
    v_group.id, auth.uid(), 'group_created', jsonb_build_object('name', v_group.name)
  );

  return v_group;
end;
$$;

grant execute on function
  create_group(text, text, int, int, int)
to authenticated;

-- ---------------------------------------------------------------------
-- memberships policies (select only — all writes go through functions)
-- ---------------------------------------------------------------------

create policy "memberships_select_fellow_member"
  on memberships for select
  using (is_group_member(group_id, auth.uid()));

-- ---------------------------------------------------------------------
-- invitations policies (select only, organizer-scoped — all writes go
-- through functions; invitees look up an invite via
-- get_invitation_preview() below, since they aren't a member yet)
-- ---------------------------------------------------------------------

create policy "invitations_select_organizer"
  on invitations for select
  using (is_group_organizer(group_id, auth.uid()));

-- ---------------------------------------------------------------------
-- audit_events policies (select only, organizer-scoped)
-- ---------------------------------------------------------------------

create policy "audit_events_select_organizer"
  on audit_events for select
  using (is_group_organizer(group_id, auth.uid()));

-- ---------------------------------------------------------------------
-- RPC: create_invitation
--   Organizer-only. Generates a random token, stores only its hash,
--   and returns the raw token once so the UI can show/copy an invite
--   link. (Email delivery of that link arrives in Phase 4.)
-- ---------------------------------------------------------------------

create function create_invitation(p_group_id uuid, p_email text)
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

  v_token := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_token, 'sha256'), 'hex');

  insert into invitations (group_id, email_normalized, token_hash, invited_by, expires_at)
  values (p_group_id, v_email, v_token_hash, auth.uid(), v_expires_at)
  returning id into v_invitation_id;

  perform log_audit_event(
    p_group_id, auth.uid(), 'invitation_created',
    jsonb_build_object('invitation_id', v_invitation_id, 'email', v_email)
  );

  return query select v_invitation_id, v_token, v_expires_at;
exception
  when unique_violation then
    raise exception 'There is already a pending invite for this email.' using errcode = '23505';
end;
$$;

-- ---------------------------------------------------------------------
-- RPC: resend_invitation
--   Organizer-only. Rotates the token/hash and expiry on an existing
--   pending or expired invite so old, possibly-leaked links stop
--   working, and returns the new raw token.
-- ---------------------------------------------------------------------

create function resend_invitation(p_invitation_id uuid)
returns table (token text, expires_at timestamptz)
language plpgsql
security definer set search_path = public
as $$
declare
  v_group_id uuid;
  v_status invitation_status;
  v_token text;
  v_token_hash text;
  v_expires_at timestamptz := now() + interval '14 days';
begin
  select group_id, status into v_group_id, v_status
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

  v_token := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_token, 'sha256'), 'hex');

  update invitations
  set token_hash = v_token_hash,
      expires_at = v_expires_at,
      status = 'pending'
  where id = p_invitation_id;

  perform log_audit_event(
    v_group_id, auth.uid(), 'invitation_resent',
    jsonb_build_object('invitation_id', p_invitation_id)
  );

  return query select v_token, v_expires_at;
end;
$$;

-- ---------------------------------------------------------------------
-- RPC: revoke_invitation
--   Organizer-only. Marks a pending invite unusable.
-- ---------------------------------------------------------------------

create function revoke_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_group_id uuid;
  v_status invitation_status;
begin
  select group_id, status into v_group_id, v_status
  from invitations where id = p_invitation_id;

  if v_group_id is null then
    raise exception 'Invitation not found.' using errcode = 'P0002';
  end if;

  if not is_group_organizer(v_group_id, auth.uid()) then
    raise exception 'Only an organizer can revoke invites.' using errcode = '42501';
  end if;

  if v_status <> 'pending' then
    raise exception 'Only a pending invite can be revoked.' using errcode = '22023';
  end if;

  update invitations set status = 'revoked' where id = p_invitation_id;

  perform log_audit_event(
    v_group_id, auth.uid(), 'invitation_revoked',
    jsonb_build_object('invitation_id', p_invitation_id)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- RPC: get_invitation_preview
--   Callable by anyone (including signed-out visitors) who has a raw
--   token, so the invitation-acceptance screen can show "You've been
--   invited to <group> by <name>" before the person signs in.
--   Returns nothing (rather than an error) when the token doesn't
--   match anything, so we don't leak which tokens are "almost right".
-- ---------------------------------------------------------------------

create function get_invitation_preview(p_token text)
returns table (
  group_name text,
  inviter_display_name text,
  email_normalized text,
  status invitation_status,
  expires_at timestamptz
)
language sql
stable
security definer set search_path = public
as $$
  select g.name, coalesce(nullif(p.display_name, ''), 'A group organizer'),
         i.email_normalized, i.status, i.expires_at
  from invitations i
  join groups g on g.id = i.group_id
  join profiles p on p.user_id = i.invited_by
  where i.token_hash = encode(digest(p_token, 'sha256'), 'hex');
$$;

grant execute on function get_invitation_preview(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- RPC: accept_invitation
--   Requires the caller to be signed in with the same email the
--   invite was sent to. Idempotent for the "already a member" case
--   so a reused/refreshed acceptance link doesn't error confusingly.
-- ---------------------------------------------------------------------

create function accept_invitation(p_token text)
returns table (accepted_group_id uuid)
language plpgsql
security definer set search_path = public
as $$
declare
  v_invitation invitations%rowtype;
  v_caller_email text;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in to accept an invite.' using errcode = '28000';
  end if;

  select * into v_invitation
  from invitations
  where token_hash = encode(digest(p_token, 'sha256'), 'hex')
  for update;

  if v_invitation.id is null then
    raise exception 'This invite link is invalid or has already been used.' using errcode = 'P0002';
  end if;

  if v_invitation.status = 'revoked' then
    raise exception 'This invite has been revoked.' using errcode = '22023';
  end if;

  if v_invitation.status = 'expired'
     or (v_invitation.status = 'pending' and v_invitation.expires_at < now()) then
    raise exception 'This invite link has expired. Ask the organizer to resend it.' using errcode = '22023';
  end if;

  if v_invitation.status = 'accepted' and v_invitation.accepted_by = auth.uid() then
    -- Already accepted by this same person: treat as success (idempotent).
    return query select v_invitation.group_id;
    return;
  end if;

  if v_invitation.status <> 'pending' then
    raise exception 'This invite link is invalid or has already been used.' using errcode = 'P0002';
  end if;

  select lower(email) into v_caller_email from auth.users where id = auth.uid();
  if v_caller_email is distinct from v_invitation.email_normalized then
    raise exception 'This invite was sent to a different email address.' using errcode = '42501';
  end if;

  insert into memberships (group_id, user_id, role, status, invited_by)
  values (v_invitation.group_id, auth.uid(), 'member', 'active', v_invitation.invited_by)
  on conflict (group_id, user_id)
  do update set status = 'active', left_at = null;

  update invitations
  set status = 'accepted', accepted_by = auth.uid(), accepted_at = now()
  where id = v_invitation.id;

  perform log_audit_event(
    v_invitation.group_id, auth.uid(), 'invitation_accepted',
    jsonb_build_object('invitation_id', v_invitation.id)
  );

  return query select v_invitation.group_id;
end;
$$;

grant execute on function accept_invitation(text) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: remove_member
--   Organizer-only. Soft-removes a member; refuses to remove the last
--   active organizer (a group must always keep at least one).
-- ---------------------------------------------------------------------

create function remove_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_target_role membership_role;
  v_organizer_count int;
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
end;
$$;

-- ---------------------------------------------------------------------
-- RPC: leave_group
--   Self-service departure. Refuses if the caller is the last active
--   organizer.
-- ---------------------------------------------------------------------

create function leave_group(p_group_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_role membership_role;
  v_organizer_count int;
begin
  select role into v_role
  from memberships
  where group_id = p_group_id and user_id = auth.uid() and status = 'active';

  if v_role is null then
    raise exception 'You are not an active member of this group.' using errcode = 'P0002';
  end if;

  if v_role = 'organizer' then
    select count(*) into v_organizer_count
    from memberships
    where group_id = p_group_id and role = 'organizer' and status = 'active';

    if v_organizer_count <= 1 then
      raise exception 'Promote another member to organizer before leaving.'
        using errcode = '22023';
    end if;
  end if;

  update memberships
  set status = 'left', left_at = now()
  where group_id = p_group_id and user_id = auth.uid();

  perform log_audit_event(
    p_group_id, auth.uid(), 'member_left',
    jsonb_build_object('user_id', auth.uid())
  );
end;
$$;

-- ---------------------------------------------------------------------
-- RPC: set_member_role
--   Organizer-only. Promotes/demotes a member; refuses to demote the
--   last active organizer.
-- ---------------------------------------------------------------------

create function set_member_role(p_group_id uuid, p_user_id uuid, p_role membership_role)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_current_role membership_role;
  v_organizer_count int;
begin
  if not is_group_organizer(p_group_id, auth.uid()) then
    raise exception 'Only an organizer can change member roles.' using errcode = '42501';
  end if;

  select role into v_current_role
  from memberships
  where group_id = p_group_id and user_id = p_user_id and status = 'active';

  if v_current_role is null then
    raise exception 'That person is not an active member of this group.' using errcode = 'P0002';
  end if;

  if v_current_role = 'organizer' and p_role = 'member' then
    select count(*) into v_organizer_count
    from memberships
    where group_id = p_group_id and role = 'organizer' and status = 'active';

    if v_organizer_count <= 1 then
      raise exception 'A group must keep at least one organizer.' using errcode = '22023';
    end if;
  end if;

  update memberships set role = p_role
  where group_id = p_group_id and user_id = p_user_id;

  perform log_audit_event(
    p_group_id, auth.uid(), 'member_role_changed',
    jsonb_build_object('user_id', p_user_id, 'role', p_role)
  );
end;
$$;

grant select, update on groups to authenticated;
grant select on memberships to authenticated;
grant select on invitations to authenticated;
grant select on audit_events to authenticated;

grant select on groups, memberships, invitations, audit_events to anon;

grant execute on function
  create_invitation(uuid, text),
  resend_invitation(uuid),
  revoke_invitation(uuid),
  remove_member(uuid, uuid),
  leave_group(uuid),
  set_member_role(uuid, uuid, membership_role)
to authenticated;
