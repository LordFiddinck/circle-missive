begin;
create extension if not exists pgtap;

select plan(73);

-- ---------------------------------------------------------------------
-- Fixtures: two groups (A: Alice organizer + Bob member; B: Carol
-- organizer + Dave member), plus Eve who belongs to neither.
-- ---------------------------------------------------------------------

select tests.create_user('alice@example.com') as uid \gset alice_
select tests.create_user('bob@example.com')   as uid \gset bob_
select tests.create_user('carol@example.com') as uid \gset carol_
select tests.create_user('dave@example.com')  as uid \gset dave_
select tests.create_user('eve@example.com')   as uid \gset eve_

select tests.authenticate_as(:'alice_uid');
select id as group_a_id from create_group('Group A') \gset

select tests.authenticate_as(:'carol_uid');
select id as group_b_id from create_group('Group B') \gset

select tests.authenticate_as(:'alice_uid');
select token as invite_bob_token
  from create_invitation(:'group_a_id'::uuid, 'bob@example.com') \gset
select tests.authenticate_as(:'bob_uid');
select accept_invitation(:'invite_bob_token');

select tests.authenticate_as(:'carol_uid');
select token as invite_dave_token
  from create_invitation(:'group_b_id'::uuid, 'dave@example.com') \gset
select tests.authenticate_as(:'dave_uid');
select accept_invitation(:'invite_dave_token');

-- ---------------------------------------------------------------------
-- start_cycle(): authorization, one-open-cycle-per-group
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'bob_uid');
select throws_ok(
  format('select start_cycle(%L)', :'group_a_id'),
  '42501',
  'Only an organizer can start a cycle.',
  'a plain member cannot start a cycle'
);

select tests.authenticate_as(:'carol_uid');
select throws_ok(
  format('select start_cycle(%L)', :'group_a_id'),
  '42501',
  'Only an organizer can start a cycle.',
  'the organizer of a different group cannot start Group A''s cycle'
);

select tests.authenticate_as(:'alice_uid');
select id as cycle_a1_id, sequence_no as cycle_a1_seq, phase as cycle_a1_phase
  from start_cycle(:'group_a_id'::uuid) \gset
select is(:'cycle_a1_seq', '1', 'the first cycle is sequence number 1');
select is(:'cycle_a1_phase', 'question_collection', 'a new cycle opens in question_collection');

select throws_ok(
  format('select start_cycle(%L)', :'group_a_id'),
  '22023',
  'This group already has an open cycle.',
  'a second cycle cannot be started while one is already open'
);

select tests.authenticate_as(:'carol_uid');
select id as cycle_b1_id from start_cycle(:'group_b_id'::uuid) \gset
with x as (
  insert into question_proposals (cycle_id, author_id, text)
  values (:'cycle_b1_id'::uuid, :'carol_uid'::uuid, 'What''s a small win from this month?')
  returning id
)
select id as proposal_b1_id from x \gset

-- ---------------------------------------------------------------------
-- question_proposals: cross-group isolation, own-only writes, phase gating
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
with x as (
  insert into question_proposals (cycle_id, author_id, text)
  values (:'cycle_a1_id'::uuid, :'alice_uid'::uuid, 'What made you laugh this week?')
  returning id
)
select id as proposal_alice_id from x \gset

select tests.authenticate_as(:'bob_uid');
with x as (
  insert into question_proposals (cycle_id, author_id, text)
  values (:'cycle_a1_id'::uuid, :'bob_uid'::uuid, 'What''s a small win you had?')
  returning id
)
select id as proposal_bob_id from x \gset
with x as (
  insert into question_proposals (cycle_id, author_id, text)
  values (:'cycle_a1_id'::uuid, :'bob_uid'::uuid, 'Delete me later')
  returning id
)
select id as proposal_throwaway_id from x \gset

select tests.authenticate_as(:'carol_uid');
select throws_ok(
  format(
    $sql$insert into question_proposals (cycle_id, author_id, text) values (%L, %L, 'sneaking in')$sql$,
    :'cycle_a1_id', :'carol_uid'
  ),
  '42501',
  null,
  'a non-member of Group A cannot propose a question for its cycle'
);

select tests.clear_authentication();
select throws_ok(
  format(
    $sql$insert into question_proposals (cycle_id, author_id, text) values (%L, %L, 'anon attempt')$sql$,
    :'cycle_a1_id', :'eve_uid'
  ),
  '42501',
  null,
  'a signed-out visitor cannot propose a question'
);

select tests.authenticate_as(:'bob_uid');
select throws_ok(
  format(
    $sql$insert into question_proposals (cycle_id, author_id, text) values (%L, %L, 'impersonation attempt')$sql$,
    :'cycle_a1_id', :'alice_uid'
  ),
  '42501',
  null,
  'a member cannot insert a proposal attributed to someone else'
);

select tests.authenticate_as(:'alice_uid');
select is(
  (select count(*)::int from question_proposals where cycle_id = :'cycle_a1_id'),
  3,
  'the organizer sees all three real proposals in her cycle'
);

select tests.authenticate_as(:'carol_uid');
select is(
  (select count(*)::int from question_proposals where cycle_id = :'cycle_a1_id'),
  0,
  'the organizer of a different group sees none of Group A''s proposals'
);

select tests.authenticate_as(:'bob_uid');
update question_proposals set text = 'What''s a small win you had this week?'
  where id = :'proposal_bob_id';
select is(
  (select text from question_proposals where id = :'proposal_bob_id'),
  'What''s a small win you had this week?',
  'a member can edit their own proposal'
);

update question_proposals set text = 'hijacked' where id = :'proposal_alice_id';
select is(
  (select count(*)::int from question_proposals where id = :'proposal_alice_id' and text = 'hijacked'),
  0,
  'a member cannot edit someone else''s proposal (RLS silently affects 0 rows)'
);

delete from question_proposals where id = :'proposal_throwaway_id';
select is(
  (select count(*)::int from question_proposals where cycle_id = :'cycle_a1_id'),
  2,
  'a member can delete their own proposal'
);

delete from question_proposals where id = :'proposal_alice_id';
select is(
  (select count(*)::int from question_proposals where id = :'proposal_alice_id'),
  1,
  'a member cannot delete someone else''s proposal (RLS silently affects 0 rows)'
);

-- ---------------------------------------------------------------------
-- finalize_questions(): authorization, validation, phase transition
-- ---------------------------------------------------------------------

select throws_ok(
  format('select finalize_questions(%L, array[%L]::uuid[])', :'cycle_a1_id', :'proposal_alice_id'),
  '42501',
  'Only an organizer can finalize questions.',
  'a plain member cannot finalize questions'
);

select tests.authenticate_as(:'carol_uid');
select throws_ok(
  format('select finalize_questions(%L, array[%L]::uuid[])', :'cycle_a1_id', :'proposal_alice_id'),
  '42501',
  'Only an organizer can finalize questions.',
  'the organizer of a different group cannot finalize Group A''s questions'
);

select tests.authenticate_as(:'alice_uid');
select throws_ok(
  format('select finalize_questions(%L, array[%L]::uuid[])', :'cycle_a1_id', :'proposal_b1_id'),
  '22023',
  'One of the selected questions does not belong to this cycle.',
  'finalize_questions rejects a proposal from a different cycle'
);

select throws_ok(
  format('select finalize_questions(%L, array[%L, %L]::uuid[])',
    :'cycle_a1_id', :'proposal_alice_id', :'proposal_alice_id'),
  '22023',
  'The same question was selected more than once.',
  'finalize_questions rejects duplicate selections'
);

select throws_ok(
  format('select finalize_questions(%L, array[]::uuid[])', :'cycle_a1_id'),
  '22023',
  'Select at least one question.',
  'finalize_questions rejects an empty selection'
);

select lives_ok(
  format('select finalize_questions(%L, array[%L, %L]::uuid[])',
    :'cycle_a1_id', :'proposal_alice_id', :'proposal_bob_id'),
  'the organizer can finalize an ordered selection of proposals'
);

select is(
  (select count(*)::int from cycle_questions where cycle_id = :'cycle_a1_id'),
  2,
  'finalizing creates one cycle_questions row per selected proposal'
);
select is(
  (select text from cycle_questions where cycle_id = :'cycle_a1_id' and position = 0),
  'What made you laugh this week?',
  'question order matches the order the organizer selected'
);
select is(
  (select phase::text from cycles where id = :'cycle_a1_id'),
  'answering',
  'finalizing questions moves the cycle into the answering phase'
);

select throws_ok(
  format('select finalize_questions(%L, array[%L]::uuid[])', :'cycle_a1_id', :'proposal_bob_id'),
  '22023',
  'Questions can only be finalized during the question phase.',
  'questions cannot be finalized twice for the same cycle'
);

select throws_ok(
  format(
    $sql$insert into question_proposals (cycle_id, author_id, text) values (%L, %L, 'too late')$sql$,
    :'cycle_a1_id', :'alice_uid'
  ),
  '42501',
  null,
  'a new proposal cannot be added once the question phase has closed'
);

select id as q1_id from cycle_questions where cycle_id = :'cycle_a1_id' and position = 0 \gset
select id as q2_id from cycle_questions where cycle_id = :'cycle_a1_id' and position = 1 \gset

select is(
  (select count(*)::int from answers a join cycle_questions cq on cq.id = a.question_id
     where cq.cycle_id = :'cycle_a1_id'),
  2,
  'finalize_questions pre-creates one empty draft answer per question for the organizer'
);
select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from answers a join cycle_questions cq on cq.id = a.question_id
     where cq.cycle_id = :'cycle_a1_id'),
  2,
  'finalize_questions pre-creates one empty draft answer per question for the member too'
);

-- ---------------------------------------------------------------------
-- answers: draft autosave and cross-member privacy
-- ---------------------------------------------------------------------

update answers set body = 'I laughed at a dog video.'
  where question_id = :'q1_id' and author_id = :'bob_uid';
select is(
  (select body from answers where question_id = :'q1_id' and author_id = :'bob_uid'),
  'I laughed at a dog video.',
  'a member can autosave their own draft answer'
);
select is(
  (select revision from answers where question_id = :'q1_id' and author_id = :'bob_uid'),
  1,
  'changing the body bumps the answer''s revision counter'
);

update answers set body = 'hacked'
  where question_id = :'q1_id' and author_id = :'alice_uid';
select is(
  (select count(*)::int from answers where question_id = :'q1_id' and author_id = :'alice_uid' and body = 'hacked'),
  0,
  'a member cannot write into another member''s answer row (RLS silently affects 0 rows)'
);

select is(
  (select count(*)::int from answers where author_id = :'alice_uid'),
  0,
  'a member cannot read another member''s draft answer at all'
);

select tests.authenticate_as(:'eve_uid');
select is(
  (select count(*)::int from answers a join cycle_questions cq on cq.id = a.question_id
     where cq.cycle_id = :'cycle_a1_id'),
  0,
  'a non-member cannot read any draft answers for the cycle'
);

-- ---------------------------------------------------------------------
-- submit_answers(): completeness validation, authorization, idempotency
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'bob_uid');
select throws_ok(
  format('select submit_answers(%L)', :'cycle_a1_id'),
  '22023',
  'Answer every question before submitting.',
  'submit_answers refuses to submit while a question is still blank'
);

update answers set body = 'Finished a big project at work.'
  where question_id = :'q2_id' and author_id = :'bob_uid';

select tests.authenticate_as(:'eve_uid');
select throws_ok(
  format('select submit_answers(%L)', :'cycle_a1_id'),
  '42501',
  'You are not a member of this group.',
  'a non-member cannot submit answers for the cycle'
);

select tests.authenticate_as(:'bob_uid');
select lives_ok(
  format('select submit_answers(%L)', :'cycle_a1_id'),
  'a member can submit once every question has a draft'
);
select is(
  (select count(*)::int from answers where author_id = :'bob_uid' and submitted_at is not null),
  2,
  'submitting marks both of the member''s answers as submitted'
);

update answers set body = 'edited after submit'
  where question_id = :'q1_id' and author_id = :'bob_uid';
select is(
  (select body from answers where question_id = :'q1_id' and author_id = :'bob_uid'),
  'I laughed at a dog video.',
  'a submitted answer can no longer be edited directly (RLS silently affects 0 rows)'
);

select lives_ok(
  format('select submit_answers(%L)', :'cycle_a1_id'),
  'resubmitting is idempotent, not an error'
);

-- ---------------------------------------------------------------------
-- get_cycle_progress(): organizer-only, completion without draft text
-- ---------------------------------------------------------------------

select throws_ok(
  format('select * from get_cycle_progress(%L)', :'cycle_a1_id'),
  '42501',
  'Only an organizer can view cycle progress.',
  'a plain member cannot view cycle progress'
);

select tests.authenticate_as(:'carol_uid');
select throws_ok(
  format('select * from get_cycle_progress(%L)', :'cycle_a1_id'),
  '42501',
  'Only an organizer can view cycle progress.',
  'the organizer of a different group cannot view Group A''s cycle progress'
);

select tests.authenticate_as(:'alice_uid');
select is(
  (select questions_answered from get_cycle_progress(:'cycle_a1_id') where user_id = :'bob_uid'),
  2,
  'the organizer''s progress view shows how many questions a member has answered'
);
select is(
  (select submitted from get_cycle_progress(:'cycle_a1_id') where user_id = :'bob_uid'),
  true,
  'the organizer''s progress view shows a member as submitted'
);
select is(
  (select submitted from get_cycle_progress(:'cycle_a1_id') where user_id = :'alice_uid'),
  false,
  'the organizer''s progress view shows the organizer''s own answers as not yet submitted'
);

-- ---------------------------------------------------------------------
-- reopen_submission()
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'carol_uid');
select throws_ok(
  format('select reopen_submission(%L, %L)', :'cycle_a1_id', :'bob_uid'),
  '42501',
  'Only an organizer can reopen a submission.',
  'the organizer of a different group cannot reopen Group A''s submission'
);

select tests.authenticate_as(:'alice_uid');
select lives_ok(
  format('select reopen_submission(%L, %L)', :'cycle_a1_id', :'bob_uid'),
  'the organizer can reopen a member''s submission'
);

select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from answers where author_id = :'bob_uid' and submitted_at is null),
  2,
  'reopening clears submitted_at on both of the member''s answers'
);
select lives_ok(
  format('select submit_answers(%L)', :'cycle_a1_id'),
  'the member can resubmit after being reopened'
);

-- ---------------------------------------------------------------------
-- change_cycle_deadline()
-- ---------------------------------------------------------------------

select throws_ok(
  format('select change_cycle_deadline(%L, %L)', :'cycle_a1_id', (now() + interval '3 days')::text),
  '42501',
  'Only an organizer can change cycle timing.',
  'a plain member cannot change the cycle deadline'
);

select tests.authenticate_as(:'alice_uid');
select lives_ok(
  format('select change_cycle_deadline(%L, %L)', :'cycle_a1_id', (now() + interval '3 days')::text),
  'the organizer can extend the answer deadline'
);
select ok(
  (select answer_due_at from cycles where id = :'cycle_a1_id') > now() + interval '2 days',
  'the extended deadline was actually stored'
);

select throws_ok(
  format('select change_cycle_deadline(%L, %L)', :'cycle_a1_id', (now() - interval '1 hour')::text),
  '22023',
  'The new deadline must be in the future.',
  'a deadline cannot be moved into the past'
);

-- ---------------------------------------------------------------------
-- publish_cycle(): snapshotting, idempotency, unsubmitted drafts excluded
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'bob_uid');
select throws_ok(
  format('select publish_cycle(%L)', :'cycle_a1_id'),
  '42501',
  'Only an organizer can publish a cycle.',
  'a plain member cannot publish the cycle'
);

select tests.authenticate_as(:'alice_uid');
select lives_ok(
  format('select publish_cycle(%L)', :'cycle_a1_id'),
  'the organizer can publish a cycle that is open for answering'
);
select is(
  (select phase::text from cycles where id = :'cycle_a1_id'),
  'published',
  'publishing moves the cycle to the published phase'
);
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_a1_id'),
  2,
  'publishing snapshots exactly the submitted answers (both of Bob''s)'
);
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_a1_id' and author_id = :'alice_uid'),
  0,
  'the organizer''s own unsubmitted draft is not included in the published issue'
);

select lives_ok(
  format('select publish_cycle(%L)', :'cycle_a1_id'),
  'publishing an already-published cycle is a no-op, not an error'
);
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_a1_id'),
  2,
  'a retried publish does not create duplicate issue entries'
);

-- ---------------------------------------------------------------------
-- issue_entries visibility
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'eve_uid');
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_a1_id'),
  0,
  'a non-member cannot read the published issue'
);

select tests.authenticate_as(:'carol_uid');
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_a1_id'),
  0,
  'the organizer of a different group cannot read Group A''s published issue'
);

select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_a1_id'),
  2,
  'a member of the group can read the published issue'
);

-- ---------------------------------------------------------------------
-- submit_late_answer(): adding an answer after publication
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'eve_uid');
select throws_ok(
  format('select submit_late_answer(%L, %L)', :'q1_id', 'sneaking in'),
  '42501',
  'You are not a member of this group.',
  'a non-member cannot add a late answer'
);

select tests.authenticate_as(:'alice_uid');
select throws_ok(
  format('select submit_late_answer(%L, %L)', :'q1_id', ''),
  '22023',
  'Enter an answer before submitting.',
  'a blank late answer is rejected'
);

select lives_ok(
  format('select submit_late_answer(%L, %L)', :'q1_id', 'Sorry, catching up late!'),
  'the organizer can add her own late answer after publication'
);
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_a1_id'),
  3,
  'the late answer adds one more entry to the published issue'
);
select is(
  (select is_late from issue_entries where question_id = :'q1_id' and author_id = :'alice_uid'),
  true,
  'the late answer is labeled as added later'
);

-- Adding a "late" answer only makes sense once a cycle has actually
-- published — prove it's rejected before then, using Group B's cycle.
select tests.authenticate_as(:'carol_uid');
select lives_ok(
  format('select finalize_questions(%L, array[%L]::uuid[])', :'cycle_b1_id', :'proposal_b1_id'),
  'Group B''s organizer can finalize her own cycle independently of Group A'
);
select id as qb1_id from cycle_questions where cycle_id = :'cycle_b1_id' and position = 0 \gset

select tests.authenticate_as(:'dave_uid');
select throws_ok(
  format('select submit_late_answer(%L, %L)', :'qb1_id', 'too early'),
  '22023',
  'This is for adding an answer after a cycle has already published — answer normally before then.',
  'submit_late_answer refuses to run on a cycle that has not published yet'
);

-- ---------------------------------------------------------------------
-- skip_cycle()
-- ---------------------------------------------------------------------

select throws_ok(
  format('select skip_cycle(%L)', :'cycle_b1_id'),
  '42501',
  'Only an organizer can skip a cycle.',
  'a plain member cannot skip a cycle'
);

select tests.authenticate_as(:'carol_uid');
select lives_ok(
  format('select skip_cycle(%L)', :'cycle_b1_id'),
  'the organizer can skip an open cycle'
);
select is(
  (select phase::text from cycles where id = :'cycle_b1_id'),
  'skipped',
  'skipping moves the cycle to the skipped phase'
);

select throws_ok(
  format('select skip_cycle(%L)', :'cycle_b1_id'),
  '22023',
  'Only an open cycle can be skipped.',
  'an already-skipped cycle cannot be skipped again'
);

select id as cycle_b2_id from start_cycle(:'group_b_id'::uuid) \gset
select is(
  (select sequence_no from cycles where group_id = :'group_b_id' order by sequence_no desc limit 1),
  2,
  'a new cycle can be started after the previous one was skipped'
);

select * from finish();
rollback;
