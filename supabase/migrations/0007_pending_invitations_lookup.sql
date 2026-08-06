-- Phase 6: pending-invitations-on-dashboard support
--
--   `invitations` has no select policy for invitees (see 0002's
--   comment: "invitees look up an invite via get_invitation_preview"),
--   and that function needs the raw token, which the app never stores
--   (only token_hash) and therefore can't hand back to an already
--   signed-in user. So: a SECURITY DEFINER function to list invites
--   addressed to the caller's own verified email, and a second one to
--   accept by id instead of by token for that same already-verified
--   case. accept_invitation_by_id mirrors accept_invitation's checks
--   line-for-line (revoked / expired / already-accepted-by-self /
--   wrong email) so the two acceptance paths stay equivalent.

create function list_my_pending_invitations()
returns table (
  invitation_id uuid,
  group_id uuid,
  group_name text,
  inviter_display_name text,
  expires_at timestamptz
)
language sql
stable
security definer set search_path = public
as $$
  select i.id, i.group_id, g.name,
         coalesce(nullif(p.display_name, ''), 'A group organizer'),
         i.expires_at
  from invitations i
  join groups g on g.id = i.group_id
  join profiles p on p.user_id = i.invited_by
  where i.status = 'pending'
    and i.expires_at > now()
    and i.email_normalized = (select lower(email) from auth.users where id = auth.uid())
  order by i.created_at desc;
$$;

grant execute on function list_my_pending_invitations() to authenticated;

create function accept_invitation_by_id(p_invitation_id uuid)
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
  where id = p_invitation_id
  for update;

  if v_invitation.id is null then
    raise exception 'This invite no longer exists.' using errcode = 'P0002';
  end if;

  select lower(email) into v_caller_email from auth.users where id = auth.uid();
  if v_caller_email is distinct from v_invitation.email_normalized then
    raise exception 'This invite was sent to a different email address.' using errcode = '42501';
  end if;

  if v_invitation.status = 'revoked' then
    raise exception 'This invite has been revoked.' using errcode = '22023';
  end if;

  if v_invitation.status = 'expired'
     or (v_invitation.status = 'pending' and v_invitation.expires_at < now()) then
    raise exception 'This invite has expired. Ask the organizer to resend it.' using errcode = '22023';
  end if;

  if v_invitation.status = 'accepted' and v_invitation.accepted_by = auth.uid() then
    -- Already accepted by this same person: treat as success (idempotent).
    return query select v_invitation.group_id;
    return;
  end if;

  if v_invitation.status <> 'pending' then
    raise exception 'This invite is no longer available.' using errcode = 'P0002';
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
    jsonb_build_object('invitation_id', v_invitation.id, 'via', 'dashboard')
  );

  return query select v_invitation.group_id;
end;
$$;

grant execute on function accept_invitation_by_id(uuid) to authenticated;
