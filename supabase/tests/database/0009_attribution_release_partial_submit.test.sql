begin;
create extension if not exists pgtap;

select plan(35);

-- ---------------------------------------------------------------------
-- Fixtures
--   Group G (Alice organizer; Bob, Carol, Dave members): the manual
--   flow — attribution, release_questions(), partial submit, manual
--   publish with auto-submit.
--   Group H (Hank, sole organizer): a cycle with no suggestions.
--   Group S (Sam organizer, Sue member): scheduler auto-release, then
--   scheduler auto-publish with auto-submit.
--   Group T (Tina, sole organizer): scheduler with no suggestions.
--   Group U (Uma, sole organizer): scheduler with 51 suggestions.
-- ---------------------------------------------------------------------

select tests.create_user('alice@example.com') as uid \gset alice_
select tests.create_user('bob@example.com')   as uid \gset bob_
select tests.create_user('carol@example.com') as uid \gset carol_
select tests.create_user('dave@example.com')  as uid \gset dave_
select tests.create_user('hank@example.com')  as uid \gset hank_
select tests.create_user('sam@example.com')   as uid \gset sam_
select tests.create_user('sue@example.com')   as uid \gset sue_
select tests.create_user('tina@example.com')  as uid \gset tina_
select tests.create_user('uma@example.com')   as uid \gset uma_

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
select id as cycle_h_id from start_cycle(:'group_h_id'::uuid) \gset

select tests.authenticate_as(:'sam_uid');
select id as group_s_id from create_group('Group S', 'UTC', 28, 1, 1) \gset
select token as t_sue from create_invitation(:'group_s_id'::uuid, 'sue@example.com') \gset
select tests.authenticate_as(:'sue_uid');
select accept_invitation(:'t_sue');

select tests.authenticate_as(:'tina_uid');
select id as group_t_id from create_group('Group T', 'UTC', 28, 1, 1) \gset

select tests.authenticate_as(:'uma_uid');
select id as group_u_id from create_group('Group U', 'UTC', 28, 1, 1) \gset

-- ---------------------------------------------------------------------
-- Attribution: show_author on proposals
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
select id as cycle_g_id from start_cycle(:'group_g_id'::uuid) \gset

-- Explicit created_at values: now() is frozen inside a test
-- transaction, so "in the order suggested" needs distinct timestamps.
insert into question_proposals (cycle_id, author_id, text, created_at)
values (:'cycle_g_id'::uuid, :'alice_uid'::uuid, 'Alice''s question', now() - interval '3 hours')
returning id as p_alice \gset

select is(
  (select show_author from question_proposals where id = :'p_alice'),
  true,
  'a proposal shows its author by default'
);

select tests.authenticate_as(:'bob_uid');
insert into question_proposals (cycle_id, author_id, text, show_author, created_at)
values (:'cycle_g_id'::uuid, :'bob_uid'::uuid, 'Bob''s anonymous question', false, now() - interval '2 hours')
returning id as p_bob \gset

select is(
  (select show_author from question_proposals where id = :'p_bob'),
  false,
  'a member can choose to hide their name on a proposal'
);

update question_proposals set show_author = true where id = :'p_bob';
select is(
  (select show_author from question_proposals where id = :'p_bob'),
  true,
  'an author can turn the name back on for their own proposal'
);
update question_proposals set show_author = false where id = :'p_bob';
select is(
  (select show_author from question_proposals where id = :'p_bob'),
  false,
  'an author can turn the name off again for their own proposal'
);

select tests.authenticate_as(:'carol_uid');
insert into question_proposals (cycle_id, author_id, text, created_at)
values (:'cycle_g_id'::uuid, :'carol_uid'::uuid, 'Carol''s question', now() - interval '1 hour');

update question_proposals set show_author = false where id = :'p_alice';
select is(
  (select show_author from question_proposals where id = :'p_alice'),
  true,
  'a member cannot change the attribution of someone else''s proposal'
);

-- ---------------------------------------------------------------------
-- release_questions()
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'bob_uid');
select throws_ok(
  format('select release_questions(%L)', :'cycle_g_id'),
  '42501',
  'Only an organizer can release questions.',
  'a plain member cannot release questions'
);

select tests.authenticate_as(:'hank_uid');
select throws_ok(
  format('select release_questions(%L)', :'cycle_h_id'),
  '22023',
  'No questions have been suggested yet.',
  'releasing with no suggestions is refused'
);

-- Dave writes nothing yet; he only matters later (removed member).
select tests.authenticate_as(:'alice_uid');
select lives_ok(
  format('select release_questions(%L)', :'cycle_g_id'),
  'the organizer can release every suggestion in one call'
);

select is(
  (select phase::text from cycles where id = :'cycle_g_id'),
  'answering',
  'releasing questions opens the cycle for answering'
);
select is(
  (select array_agg(text order by position) from cycle_questions where cycle_id = :'cycle_g_id'),
  array['Alice''s question', 'Bob''s anonymous question', 'Carol''s question'],
  'released questions keep the order in which they were suggested'
);

select id as qg1 from cycle_questions where cycle_id = :'cycle_g_id' and position = 0 \gset
select id as qg2 from cycle_questions where cycle_id = :'cycle_g_id' and position = 1 \gset
select id as qg3 from cycle_questions where cycle_id = :'cycle_g_id' and position = 2 \gset

select tests.authenticate_as(:'carol_uid');
select is(
  (select asked_by from cycle_questions where id = :'qg1'),
  :'alice_uid'::uuid,
  'a question whose author opted in is attributed to them, visible to other members'
);
select is(
  (select asked_by from cycle_questions where id = :'qg2'),
  null::uuid,
  'a question whose author opted out carries no attribution at all'
);

select tests.authenticate_as(:'alice_uid');
select throws_ok(
  format('select release_questions(%L)', :'cycle_g_id'),
  '22023',
  'Questions can only be finalized during the question phase.',
  'questions cannot be released twice'
);

select throws_ok(
  format('select finalize_questions_internal(%L, array[%L]::uuid[], null)', :'cycle_h_id', :'p_alice'),
  '42501',
  'permission denied for function finalize_questions_internal',
  'a signed-in user cannot call the internal finalize function directly'
);

-- ---------------------------------------------------------------------
-- Partial submission
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'carol_uid');
update answers set body = 'Carol answered only the first one.'
  where question_id = :'qg1' and author_id = :'carol_uid';

select lives_ok(
  format('select submit_answers(%L)', :'cycle_g_id'),
  'a member can submit with some questions left blank'
);
select is(
  (select count(*)::int from answers where author_id = :'carol_uid' and submitted_at is not null),
  3,
  'a partial submission marks all of the member''s answers as submitted'
);

select tests.authenticate_as(:'alice_uid');
select is(
  (select (questions_answered::text || '/' || submitted::text)
     from get_cycle_progress(:'cycle_g_id') where user_id = :'carol_uid'),
  '1/true',
  'the organizer sees a partial submission as 1 answered and submitted'
);

-- ---------------------------------------------------------------------
-- Auto-submit when the organizer publishes by hand
-- ---------------------------------------------------------------------

-- Bob saves a draft but never presses Submit.
select tests.authenticate_as(:'bob_uid');
update answers set body = 'Bob''s saved-but-unsubmitted draft.'
  where question_id = :'qg2' and author_id = :'bob_uid';

-- Dave saves a draft and is then removed from the group.
select tests.authenticate_as(:'dave_uid');
update answers set body = 'Dave''s draft, written before he left.'
  where question_id = :'qg1' and author_id = :'dave_uid';

select tests.authenticate_as(:'alice_uid');
select remove_member(:'group_g_id'::uuid, :'dave_uid'::uuid);

select lives_ok(
  format('select publish_cycle(%L)', :'cycle_g_id'),
  'the organizer can publish while a member has only saved drafts'
);
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_g_id' and author_id = :'bob_uid'),
  1,
  'a member''s saved draft is auto-submitted and published'
);
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_g_id' and author_id = :'carol_uid'),
  1,
  'blank answers from a partial submission are not published as entries'
);
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_g_id' and author_id = :'dave_uid'),
  0,
  'a removed member''s unsubmitted draft is not auto-submitted'
);
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_g_id' and author_id = :'alice_uid'),
  0,
  'a member with no written answers gets no entries'
);
select is(
  (select (metadata ->> 'auto_submitted_members')::int from audit_events
    where group_id = :'group_g_id' and event_type = 'cycle_published'),
  1,
  'the publish audit event records how many members were auto-submitted'
);

-- A skipped question can still be answered after publication.
select tests.authenticate_as(:'carol_uid');
select lives_ok(
  format('select submit_late_answer(%L, %L)', :'qg3', 'Carol answers late.'),
  'a member who left a question blank can add it after publication'
);

-- ---------------------------------------------------------------------
-- Scheduler: auto-release when the question phase ends
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'sam_uid');
select id as cycle_s_id from start_cycle(:'group_s_id'::uuid) \gset
insert into question_proposals (cycle_id, author_id, text)
values (:'cycle_s_id'::uuid, :'sam_uid'::uuid, 'S question one'),
       (:'cycle_s_id'::uuid, :'sam_uid'::uuid, 'S question two');

select tests.authenticate_as(:'tina_uid');
select id as cycle_t_id from start_cycle(:'group_t_id'::uuid) \gset

select tests.authenticate_as(:'uma_uid');
select id as cycle_u_id from start_cycle(:'group_u_id'::uuid) \gset
insert into question_proposals (cycle_id, author_id, text, created_at)
select :'cycle_u_id'::uuid, :'uma_uid'::uuid, 'U question ' || g, now() - make_interval(mins => 100 - g)
from generate_series(1, 51) g;

select tests.become_service_role();
update cycles set question_closes_at = now() - interval '1 hour'
  where id in (:'cycle_s_id', :'cycle_t_id', :'cycle_u_id');
update cycles set next_action_at = now() - interval '1 minute'
  where id in (:'cycle_s_id', :'cycle_t_id', :'cycle_u_id');

select scheduler_tick(50);

select is(
  (select phase::text from cycles where id = :'cycle_s_id'),
  'answering',
  'the scheduler releases suggestions once the question phase has ended'
);
select is(
  (select count(*)::int from cycle_questions where cycle_id = :'cycle_s_id'),
  2,
  'the scheduler releases every suggestion'
);
select is(
  (select actor_id is null from audit_events
    where group_id = :'group_s_id' and event_type = 'questions_auto_finalized'),
  true,
  'the automatic release is audited with no human actor'
);
select ok(
  (select count(*)::int from email_outbox
    where group_id = :'group_s_id' and template = 'answering_opened') >= 2,
  'members are told answering has opened after an automatic release'
);
select is(
  (select count(*)::int from email_outbox
    where group_id = :'group_s_id' and template = 'question_phase_overdue'),
  0,
  'no overdue nudge is sent for a cycle the scheduler released'
);

select is(
  (select phase::text from cycles where id = :'cycle_t_id'),
  'question_collection',
  'with no suggestions the scheduler leaves the question phase open'
);
select is(
  (select count(*)::int from email_outbox
    where group_id = :'group_t_id' and template = 'question_phase_overdue'),
  1,
  'with no suggestions the organizer is nudged instead'
);
select is(
  (select count(*)::int from cycle_questions where cycle_id = :'cycle_u_id'),
  50,
  'an automatic release is capped at 50 questions rather than failing the tick'
);

-- ---------------------------------------------------------------------
-- Scheduler: auto-submit at the deadline
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'sue_uid');
update answers set body = 'Sue saved this but never submitted.'
  where author_id = :'sue_uid'
    and question_id = (select id from cycle_questions where cycle_id = :'cycle_s_id' and position = 0);

select tests.become_service_role();
update cycles set answer_due_at = now() - interval '1 hour' where id = :'cycle_s_id';
update cycles set next_action_at = now() - interval '1 minute' where id = :'cycle_s_id';

select scheduler_tick(50);

select is(
  (select phase::text from cycles where id = :'cycle_s_id'),
  'published',
  'a released cycle is auto-published at its deadline'
);
select is(
  (select count(*)::int from issue_entries where cycle_id = :'cycle_s_id' and author_id = :'sue_uid'),
  1,
  'a draft saved but never submitted is submitted automatically at the deadline'
);
select is(
  (select (metadata ->> 'auto_submitted_members')::int from audit_events
    where group_id = :'group_s_id' and event_type = 'cycle_auto_published'),
  1,
  'the automatic publish records how many members were auto-submitted'
);

select * from finish();
rollback;
