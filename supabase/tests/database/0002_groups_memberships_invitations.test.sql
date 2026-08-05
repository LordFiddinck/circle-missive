begin;
create extension if not exists pgtap;

select plan(49);

-- ---------------------------------------------------------------------
-- Fixtures: two groups, each with an organizer and a member, plus an
-- outsider who belongs to neither. This is the minimum shape needed to
-- prove cross-group isolation, not just "signed out vs signed in".
-- ---------------------------------------------------------------------

select tests.create_user('alice@example.com') as uid \gset alice_
select tests.create_user('bob@example.com')   as uid \gset bob_
select tests.create_user('carol@example.com') as uid \gset carol_
select tests.create_user('dave@example.com')  as uid \gset dave_
select tests.create_user('eve@example.com')   as uid \gset eve_

-- Alice creates Group A and becomes its organizer atomically via
-- create_group().
select tests.authenticate_as(:'alice_uid');
select id as group_a_id from create_group('Group A') \gset

-- Carol creates Group B the same way.
select tests.authenticate_as(:'carol_uid');
select id as group_b_id from create_group('Group B') \gset

-- Alice invites Bob into Group A and he accepts.
select tests.authenticate_as(:'alice_uid');
select token as invite_a_bob_token
  from create_invitation(:'group_a_id'::uuid, 'bob@example.com') \gset

select tests.authenticate_as(:'bob_uid');
select accept_invitation(:'invite_a_bob_token');

-- Carol invites Dave into Group B and he accepts.
select tests.authenticate_as(:'carol_uid');
select token as invite_b_dave_token
  from create_invitation(:'group_b_id'::uuid, 'dave@example.com') \gset

select tests.authenticate_as(:'dave_uid');
select accept_invitation(:'invite_b_dave_token');

-- ---------------------------------------------------------------------
-- groups: select isolation
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
select is(
  (select count(*)::int from groups),
  1,
  'organizer sees only their own group, not other groups'
);

select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from groups),
  1,
  'member sees only the group they belong to'
);

select tests.authenticate_as(:'eve_uid');
select is(
  (select count(*)::int from groups),
  0,
  'an outsider with no membership sees zero groups'
);

select tests.clear_authentication();
select is(
  (select count(*)::int from groups),
  0,
  'a signed-out visitor sees zero groups'
);

-- ---------------------------------------------------------------------
-- groups: update authorization
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'bob_uid');
update groups set name = 'Hijacked by Bob' where id = :'group_a_id';
select is(
  (select count(*)::int from groups where id = :'group_a_id' and name = 'Hijacked by Bob'),
  0,
  'a plain member cannot rename the group (RLS silently affects 0 rows)'
);

select tests.authenticate_as(:'carol_uid');
update groups set name = 'Hijacked by outsider organizer' where id = :'group_a_id';
select is(
  (select count(*)::int from groups where id = :'group_a_id' and name = 'Hijacked by outsider organizer'),
  0,
  'an organizer of a different group cannot rename Group A'
);

select tests.authenticate_as(:'alice_uid');
update groups set name = 'Group A renamed' where id = :'group_a_id';
select is(
  (select name from groups where id = :'group_a_id'),
  'Group A renamed',
  'the organizer of a group can rename it'
);

-- ---------------------------------------------------------------------
-- groups: created_by / id are immutable
-- ---------------------------------------------------------------------

select throws_ok(
  format('update groups set created_by = %L where id = %L', :'bob_uid', :'group_a_id'),
  'P0001',
  'groups.created_by is immutable',
  'organizer cannot reassign created_by to someone else'
);

select throws_ok(
  format('insert into groups (name, created_by) values (%L, %L)', 'Direct insert attack', :'alice_uid'),
  '42501',
  null,
  'nobody can insert a group row directly — only create_group() can (no INSERT policy exists)'
);

-- ---------------------------------------------------------------------
-- profiles: cross-member visibility (fellow group members only)
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
select is(
  (select count(*)::int from profiles where user_id = :'bob_uid'),
  1,
  'a member can read a fellow group member''s profile'
);
select is(
  (select count(*)::int from profiles where user_id = :'carol_uid'),
  0,
  'a member cannot read the profile of someone in a different group'
);

select tests.authenticate_as(:'eve_uid');
select is(
  (select count(*)::int from profiles where user_id = :'alice_uid'),
  0,
  'a non-member cannot read any other user''s profile'
);
select is(
  (select count(*)::int from profiles where user_id = :'eve_uid'),
  1,
  'a user can always read their own profile regardless of group membership'
);

-- ---------------------------------------------------------------------
-- memberships: select isolation (cross-group attack surface)
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
select is(
  (select count(*)::int from memberships),
  2,
  'organizer of Group A sees exactly its two memberships (self + Bob)'
);
select is(
  (select count(*)::int from memberships where group_id = :'group_b_id'),
  0,
  'organizer of Group A sees zero rows from Group B''s memberships'
);

select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from memberships where group_id = :'group_b_id'),
  0,
  'a member of Group A cannot see Group B''s membership list'
);

select tests.authenticate_as(:'eve_uid');
select is(
  (select count(*)::int from memberships),
  0,
  'a non-member sees no memberships anywhere'
);

-- No insert/update policies exist on memberships at all — direct writes
-- must fail regardless of role, because every mutation is required to
-- go through an audited function.
select tests.authenticate_as(:'alice_uid');
select throws_ok(
  format(
    'insert into memberships (group_id, user_id, role) values (%L, %L, %L)',
    :'group_a_id', :'eve_uid', 'member'
  ),
  '42501',
  null,
  'even the organizer cannot insert a membership row directly (no INSERT policy)'
);

select throws_ok(
  format('update memberships set role = %L where group_id = %L and user_id = %L',
    'organizer', :'group_a_id', :'bob_uid'),
  '42501',
  null,
  'even the organizer cannot update a membership row directly (no UPDATE policy)'
);

-- ---------------------------------------------------------------------
-- invitations: select isolation and no direct writes
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
select is(
  (select count(*)::int from invitations),
  1,
  'organizer of Group A sees exactly Group A''s invitation history'
);

select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from invitations),
  0,
  'a plain member cannot see the group''s invitation history'
);

select tests.authenticate_as(:'carol_uid');
select is(
  (select count(*)::int from invitations where group_id = :'group_a_id'),
  0,
  'organizer of Group B cannot see Group A''s invitations'
);

select throws_ok(
  format(
    $sql$insert into invitations (group_id, email_normalized, token_hash, invited_by, expires_at)
         values (%L, 'mallory@example.com', 'x', %L, now() + interval '1 day')$sql$,
    :'group_b_id', :'carol_uid'
  ),
  '42501',
  null,
  'organizer cannot insert an invitation row directly, bypassing create_invitation()'
);

-- ---------------------------------------------------------------------
-- create_invitation(): authorization and validation
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'bob_uid');
select throws_ok(
  format('select create_invitation(%L, %L)', :'group_a_id', 'mallory@example.com'),
  '42501',
  'Only an organizer can invite members.',
  'a plain member cannot create an invitation for their own group'
);

select tests.authenticate_as(:'carol_uid');
select throws_ok(
  format('select create_invitation(%L, %L)', :'group_a_id', 'mallory@example.com'),
  '42501',
  'Only an organizer can invite members.',
  'the organizer of Group B cannot invite someone into Group A'
);

select tests.authenticate_as(:'alice_uid');
select throws_ok(
  format('select create_invitation(%L, %L)', :'group_a_id', 'not-an-email'),
  '22023',
  'Enter a valid email address.',
  'create_invitation rejects a malformed email'
);

select throws_ok(
  format('select create_invitation(%L, %L)', :'group_a_id', 'bob@example.com'),
  '22023',
  'This person is already a member of the group.',
  'create_invitation refuses to invite someone already in the group'
);

select lives_ok(
  format('select create_invitation(%L, %L)', :'group_a_id', 'mallory@example.com'),
  'organizer can invite a new email address'
);

select throws_ok(
  format('select create_invitation(%L, %L)', :'group_a_id', 'MALLORY@EXAMPLE.COM'),
  '23505',
  'There is already a pending invite for this email.',
  'a second pending invite to the same email (any case) is rejected'
);

-- ---------------------------------------------------------------------
-- accept_invitation(): token validity, email match, expiry, idempotency
-- ---------------------------------------------------------------------

select throws_ok(
  $sql$select accept_invitation('not-a-real-token')$sql$,
  'P0002',
  'This invite link is invalid or has already been used.',
  'accepting a bogus token fails'
);

select tests.authenticate_as(:'alice_uid');
select token as invite_a_mallory_token
  from create_invitation(:'group_a_id'::uuid, 'mallory2@example.com') \gset

select tests.authenticate_as(:'eve_uid');
select throws_ok(
  format('select accept_invitation(%L)', :'invite_a_mallory_token'),
  '42501',
  'This invite was sent to a different email address.',
  'a signed-in user with a different email cannot accept someone else''s invite'
);

select is(
  (select count(*)::int from memberships where group_id = :'group_a_id' and user_id = :'eve_uid'),
  0,
  'the mismatched-email accept attempt created no membership row'
);

-- Reused (already-accepted) token must fail for a different accepter,
-- and re-accepting as the original accepter is idempotent.
select tests.authenticate_as(:'bob_uid');
select accept_invitation(:'invite_a_bob_token'); -- already accepted once in fixtures
select is(
  (select accepted_group_id::text from accept_invitation(:'invite_a_bob_token')),
  :'group_a_id',
  're-accepting your own already-used invite link is idempotent, not an error'
);

select tests.authenticate_as(:'eve_uid');
select throws_ok(
  format('select accept_invitation(%L)', :'invite_a_bob_token'),
  'P0002',
  'This invite link is invalid or has already been used.',
  'a different person cannot reuse an already-accepted invite token'
);

-- Expired invite.
select tests.authenticate_as(:'alice_uid');
select token as invite_a_expired_token, invitation_id as invite_a_expired_id
  from create_invitation(:'group_a_id'::uuid, 'latecomer@example.com') \gset
reset role; -- test-harness only: simulate time passing, not a real user action
update invitations set expires_at = now() - interval '1 minute'
  where id = :'invite_a_expired_id';

-- (latecomer isn't a real user in our fixtures; we only need to prove
-- the expiry check fires before the email-match check would even run.)
select tests.authenticate_as(:'eve_uid');
select throws_ok(
  format('select accept_invitation(%L)', :'invite_a_expired_token'),
  '22023',
  'This invite link has expired. Ask the organizer to resend it.',
  'an expired invite cannot be accepted'
);

select tests.authenticate_as(:'alice_uid');
select is(
  (select status from invitations where id = :'invite_a_expired_id'),
  'pending',
  'an expired invite''s stored status stays pending — expiry is judged by expires_at, not a self-persisted flag'
);

-- ---------------------------------------------------------------------
-- get_invitation_preview(): readable pre-signin, no leakage on miss
-- ---------------------------------------------------------------------

select tests.clear_authentication();
select is(
  (select group_name from get_invitation_preview(:'invite_a_mallory_token')),
  'Group A renamed',
  'a signed-out visitor can preview a valid invite by token'
);
select is(
  (select count(*)::int from get_invitation_preview('totally-bogus-token')),
  0,
  'previewing a bogus token returns no rows rather than an error'
);

-- ---------------------------------------------------------------------
-- resend_invitation() / revoke_invitation(): organizer-only
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'carol_uid');
select throws_ok(
  format('select revoke_invitation(%L)', :'invite_a_expired_id'),
  '42501',
  'Only an organizer can revoke invites.',
  'organizer of a different group cannot revoke Group A''s invite'
);

select tests.authenticate_as(:'alice_uid');
select lives_ok(
  format('select token from resend_invitation(%L)', :'invite_a_expired_id'),
  'organizer can resend an expired invite, rotating its token'
);
select is(
  (select status from invitations where id = :'invite_a_expired_id'),
  'pending',
  'resending flips the invite back to pending'
);

select lives_ok(
  format('select revoke_invitation(%L)', :'invite_a_expired_id'),
  'organizer can revoke a pending invite'
);
select is(
  (select status from invitations where id = :'invite_a_expired_id'),
  'revoked',
  'revoking sets the invite status to revoked'
);

-- ---------------------------------------------------------------------
-- remove_member() / leave_group() / set_member_role(): last-organizer
-- guard and cross-group authorization
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'carol_uid');
select throws_ok(
  format('select remove_member(%L, %L)', :'group_a_id', :'bob_uid'),
  '42501',
  'Only an organizer can remove members.',
  'organizer of Group B cannot remove a member of Group A'
);

select tests.authenticate_as(:'alice_uid');
select throws_ok(
  format('select remove_member(%L, %L)', :'group_a_id', :'alice_uid'),
  '22023',
  'A group must keep at least one organizer. Promote another member first.',
  'the sole organizer cannot remove themselves'
);

select lives_ok(
  format('select remove_member(%L, %L)', :'group_a_id', :'bob_uid'),
  'organizer can remove a plain member'
);
select is(
  (select status from memberships where group_id = :'group_a_id' and user_id = :'bob_uid'),
  'removed',
  'removed member''s row is soft-deleted (status=removed), not hard-deleted'
);

select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from groups where id = :'group_a_id'),
  0,
  'a removed member immediately loses read access to the group'
);

select tests.authenticate_as(:'alice_uid');
select throws_ok(
  format('select leave_group(%L)', :'group_a_id'),
  '22023',
  'Promote another member to organizer before leaving.',
  'the sole organizer cannot leave via leave_group either'
);

select * from finish();
rollback;
