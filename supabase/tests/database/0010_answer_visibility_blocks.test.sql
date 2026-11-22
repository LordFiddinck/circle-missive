begin;
create extension if not exists pgtap;

select plan(29);

-- ---------------------------------------------------------------------
-- Fixtures
--   Group G: Alice (organizer), Bob, Carol, Dave. Everyone but Dave
--   answers in a published issue.
--   Group H: Hank (organizer), unrelated.
--   Eve: not in either group.
-- ---------------------------------------------------------------------

select tests.create_user('alice@example.com') as uid \gset alice_
select tests.create_user('bob@example.com')   as uid \gset bob_
select tests.create_user('carol@example.com') as uid \gset carol_
select tests.create_user('dave@example.com')  as uid \gset dave_
select tests.create_user('hank@example.com')  as uid \gset hank_
select tests.create_user('eve@example.com')   as uid \gset eve_

select tests.authenticate_as(:'alice_uid');
select id as group_g_id from create_group('Group G', 'UTC', 28, 1, 1) \gset
select token as t_bob   from create_invitation(:'group_g_id'::uuid, 'bob@example.com')   \gset
select token as t_carol from create_invitation(:'group_g_id'::uuid, 'carol@example.com') \gset
select token as t_dave  from create_invitation(:'group_g_id'::uuid, 'dave@example.com')  \gset
select tests.authenticate_as(:'bob_uid');
select accept_invitation(:'t_bob');
select tests.authenticate_as(:'carol_uid');
select accept_invitation(:'t_carol');
select tests.authenticate_as(:'dave_uid');
select accept_invitation(:'t_dave');

select tests.authenticate_as(:'hank_uid');
select id as group_h_id from create_group('Group H', 'UTC', 28, 1, 1) \gset

-- One published cycle with two questions; Alice, Bob and Carol answer.
select tests.authenticate_as(:'alice_uid');
select id as cycle_id from start_cycle(:'group_g_id'::uuid) \gset
insert into question_proposals (cycle_id, author_id, text, created_at)
values (:'cycle_id'::uuid, :'alice_uid'::uuid, 'Question one', now() - interval '2 hours'),
       (:'cycle_id'::uuid, :'alice_uid'::uuid, 'Question two', now() - interval '1 hour');
select release_questions(:'cycle_id'::uuid);
select id as q1 from cycle_questions where cycle_id = :'cycle_id' and position = 0 \gset
select id as q2 from cycle_questions where cycle_id = :'cycle_id' and position = 1 \gset

update answers set body = 'Alice one' where question_id = :'q1' and author_id = :'alice_uid';
update answers set body = 'Alice two' where question_id = :'q2' and author_id = :'alice_uid';
select submit_answers(:'cycle_id'::uuid);
select tests.authenticate_as(:'bob_uid');
update answers set body = 'Bob one' where question_id = :'q1' and author_id = :'bob_uid';
update answers set body = 'Bob two' where question_id = :'q2' and author_id = :'bob_uid';
select submit_answers(:'cycle_id'::uuid);
select tests.authenticate_as(:'carol_uid');
update answers set body = 'Carol one' where question_id = :'q1' and author_id = :'carol_uid';
update answers set body = 'Carol two' where question_id = :'q2' and author_id = :'carol_uid';
select submit_answers(:'cycle_id'::uuid);

select tests.authenticate_as(:'alice_uid');
select publish_cycle(:'cycle_id'::uuid);

-- ---------------------------------------------------------------------
-- Baseline: before any block, members read each other's entries
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_id'),
  6,
  'before any block, a member reads all six entries'
);

-- ---------------------------------------------------------------------
-- Who may hide / what is validated
-- ---------------------------------------------------------------------

select throws_ok(
  format('select hide_answers_between(%L, %L, %L)', :'group_g_id', :'bob_uid', :'carol_uid'),
  '42501',
  'Only an organizer can hide answers between members.',
  'a plain member cannot hide answers between two people'
);

select tests.authenticate_as(:'hank_uid');
select throws_ok(
  format('select hide_answers_between(%L, %L, %L)', :'group_g_id', :'bob_uid', :'carol_uid'),
  '42501',
  'Only an organizer can hide answers between members.',
  'an organizer of a different group cannot hide answers in this one'
);

select tests.authenticate_as(:'alice_uid');
select throws_ok(
  format('select hide_answers_between(%L, %L, %L)', :'group_g_id', :'bob_uid', :'bob_uid'),
  '22023',
  'Choose two different people.',
  'a person cannot be paired with themselves'
);
select throws_ok(
  format('select hide_answers_between(%L, %L, %L)', :'group_g_id', :'bob_uid', :'eve_uid'),
  '22023',
  'Both people must be active members of this group.',
  'both people must be members of the group'
);

-- ---------------------------------------------------------------------
-- Hiding Bob and Carol from each other
-- ---------------------------------------------------------------------

select lives_ok(
  format('select hide_answers_between(%L, %L, %L)', :'group_g_id', :'bob_uid', :'carol_uid'),
  'an organizer can hide two members'' answers from each other'
);

select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_id' and author_id = :'carol_uid'),
  0,
  'the first person can no longer read the second person''s entries'
);
select is(
  (select array_agg(distinct author_id order by author_id) from issue_entries where cycle_id = :'cycle_id'),
  (select array_agg(x order by x) from unnest(array[:'alice_uid'::uuid, :'bob_uid'::uuid]) x),
  'the first person still reads everyone else''s entries and their own'
);

select tests.authenticate_as(:'carol_uid');
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_id' and author_id = :'bob_uid'),
  0,
  'the block is symmetric: the second person cannot read the first''s entries either'
);
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_id'),
  4,
  'the second person still reads everyone else''s entries and their own'
);

select tests.authenticate_as(:'alice_uid');
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_id'),
  6,
  'members outside the pair are unaffected'
);

select tests.authenticate_as(:'dave_uid');
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_id'),
  6,
  'a member who did not answer still reads everything outside their own blocks'
);

-- The same pair given in the opposite order is the same block.
select tests.authenticate_as(:'alice_uid');
select hide_answers_between(:'group_g_id'::uuid, :'carol_uid'::uuid, :'bob_uid'::uuid);
select is(
  (select count(*)::int from answer_visibility_blocks where group_id = :'group_g_id'),
  1,
  'hiding the same pair in the opposite order does not create a second block'
);
select is(
  (select count(*)::int from audit_events
    where group_id = :'group_g_id' and event_type = 'answer_visibility_hidden'),
  1,
  'a repeated request is not audited a second time'
);

-- ---------------------------------------------------------------------
-- Late answers added after the block are hidden too
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'dave_uid');
select submit_late_answer(:'q1'::uuid, 'Dave answers late');
select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_id' and author_id = :'dave_uid'),
  1,
  'a blocked pair is only hidden from each other, not from others'' new answers'
);

-- ---------------------------------------------------------------------
-- The block list is private, and cannot be written to directly
-- ---------------------------------------------------------------------

select is(
  (select count(*)::int from answer_visibility_blocks),
  0,
  'a blocked member cannot read the block list'
);
select tests.authenticate_as(:'dave_uid');
select is(
  (select count(*)::int from answer_visibility_blocks),
  0,
  'an unrelated member cannot read the block list'
);
select tests.authenticate_as(:'alice_uid');
select is(
  (select count(*)::int from answer_visibility_blocks where group_id = :'group_g_id'),
  1,
  'an organizer can read the block list'
);

select tests.authenticate_as(:'bob_uid');
select throws_ok(
  format(
    'insert into answer_visibility_blocks (group_id, user_a, user_b) values (%L, %L, %L)',
    :'group_g_id', least(:'bob_uid'::uuid, :'dave_uid'::uuid), greatest(:'bob_uid'::uuid, :'dave_uid'::uuid)
  ),
  '42501',
  null,
  'a member cannot insert into the block list directly'
);
select throws_ok(
  format('delete from answer_visibility_blocks where group_id = %L', :'group_g_id'),
  '42501',
  null,
  'a member cannot delete from the block list directly'
);

-- ---------------------------------------------------------------------
-- The visibility check only ever answers about the caller
-- ---------------------------------------------------------------------

select is(
  is_answer_hidden_from_me(:'group_g_id'::uuid, :'carol_uid'::uuid),
  true,
  'the check says Carol''s answers are hidden from Bob'
);
select is(
  is_answer_hidden_from_me(:'group_g_id'::uuid, :'alice_uid'::uuid),
  false,
  'the check says Alice''s answers are not hidden from Bob'
);

select tests.authenticate_as(:'eve_uid');
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_id'),
  0,
  'someone outside the group still reads nothing'
);

-- ---------------------------------------------------------------------
-- Restoring
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'bob_uid');
select throws_ok(
  format('select restore_answers_between(%L, %L, %L)', :'group_g_id', :'bob_uid', :'carol_uid'),
  '42501',
  'Only an organizer can restore answer visibility.',
  'a blocked member cannot lift their own block'
);

select tests.authenticate_as(:'alice_uid');
select lives_ok(
  format('select restore_answers_between(%L, %L, %L)', :'group_g_id', :'carol_uid', :'bob_uid'),
  'an organizer can restore a pair, in either order'
);
select lives_ok(
  format('select restore_answers_between(%L, %L, %L)', :'group_g_id', :'carol_uid', :'bob_uid'),
  'restoring a pair that is not hidden is a harmless no-op'
);

select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_id' and author_id = :'carol_uid'),
  2,
  'after restoring, previously hidden entries are readable again'
);

select is(
  (select count(*)::int from audit_events
    where group_id = :'group_g_id' and event_type = 'answer_visibility_restored'),
  0,
  'a member cannot read the audit log'
);
select tests.authenticate_as(:'alice_uid');
select is(
  (select count(*)::int from audit_events
    where group_id = :'group_g_id' and event_type = 'answer_visibility_restored'),
  1,
  'restoring is audited once, and the no-op is not'
);

select * from finish();
rollback;
