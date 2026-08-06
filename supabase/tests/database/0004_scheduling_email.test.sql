begin;
create extension if not exists pgtap;

select plan(40);

-- ---------------------------------------------------------------------
-- Fixtures
--   Group A (Alice organizer, Bob member): driven to a due, unanswered
--   answering-phase cycle, to exercise scheduler_tick()'s auto-publish
--   + auto-start-next-cycle branch.
--   Group B (Carol organizer, Dave member): driven to an answering-
--   phase cycle due soon (but not yet), to exercise the reminder
--   branch without publishing.
--   Group F (Frank, sole organizer): left in question_collection past
--   its close date, to exercise the organizer-nudge branch.
-- ---------------------------------------------------------------------

select tests.create_user('alice@example.com') as uid \gset alice_
select tests.create_user('bob@example.com')   as uid \gset bob_
select tests.create_user('carol@example.com') as uid \gset carol_
select tests.create_user('dave@example.com')  as uid \gset dave_
select tests.create_user('frank@example.com') as uid \gset frank_

select tests.authenticate_as(:'alice_uid');
select id as group_a_id from create_group('Group A', 'UTC', 28, 1, 1) \gset
select token as invite_bob_token
  from create_invitation(:'group_a_id'::uuid, 'bob@example.com') \gset
select tests.authenticate_as(:'bob_uid');
select accept_invitation(:'invite_bob_token');

select tests.authenticate_as(:'carol_uid');
select id as group_b_id from create_group('Group B', 'UTC', 28, 1, 1) \gset
select token as invite_dave_token
  from create_invitation(:'group_b_id'::uuid, 'dave@example.com') \gset
select tests.authenticate_as(:'dave_uid');
select accept_invitation(:'invite_dave_token');

select tests.authenticate_as(:'frank_uid');
select id as group_f_id from create_group('Group F', 'UTC', 28, 1, 1) \gset

-- ---------------------------------------------------------------------
-- email_preferences: created automatically, own-row RLS
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
select is(
  (select reminders_enabled from email_preferences where user_id = :'alice_uid'),
  true,
  'a default email_preferences row is created alongside the profile'
);
select is(
  (select count(*)::int from email_preferences where user_id = :'bob_uid'),
  0,
  'a member cannot read another member''s email preferences'
);

select lives_ok(
  format('update email_preferences set reminders_enabled = false where user_id = %L', :'alice_uid'),
  'a user can turn off their own reminder emails'
);
select is(
  (select reminders_enabled from email_preferences where user_id = :'alice_uid'),
  false,
  'the preference change took effect'
);

select throws_ok(
  format('update email_preferences set suppressed = true where user_id = %L', :'alice_uid'),
  'P0001',
  'email_preferences.suppressed cannot be set directly.',
  'a user cannot set their own suppressed flag'
);

-- ---------------------------------------------------------------------
-- enqueue_email(): service-role only, opt-out skipping, dedupe
-- ---------------------------------------------------------------------

select throws_ok(
  $$select enqueue_email('x', null, 'a@example.com', 'group_invitation', '{}'::jsonb, null, 'transactional')$$,
  '42501',
  'permission denied for function enqueue_email',
  'an authenticated (non-service-role) caller cannot enqueue mail directly'
);

select tests.become_service_role();

select enqueue_email(
  'test:reminder:1', :'alice_uid'::uuid, 'alice@example.com', 'answer_deadline_reminder', '{}'::jsonb,
  :'group_a_id'::uuid, 'reminders'
);
select is(
  (select status::text from email_outbox where dedupe_key = 'test:reminder:1'),
  'skipped',
  'a reminder is enqueued as skipped once the recipient has opted out'
);

select enqueue_email(
  'test:invite:1', null, 'someone@example.com', 'group_invitation', '{}'::jsonb,
  :'group_a_id'::uuid, 'transactional'
);
select is(
  (select status::text from email_outbox where dedupe_key = 'test:invite:1'),
  'pending',
  'a transactional email is enqueued regardless of the reminders/announcements toggles'
);

select is(
  (select enqueue_email(
    'test:invite:1', null, 'someone@example.com', 'group_invitation', '{}'::jsonb,
    :'group_a_id'::uuid, 'transactional'
  )),
  false,
  're-enqueuing the same dedupe key is a no-op'
);
select is(
  (select count(*)::int from email_outbox where dedupe_key = 'test:invite:1'),
  1,
  'no duplicate row was created'
);

-- ---------------------------------------------------------------------
-- claim/send/fail cycle
-- ---------------------------------------------------------------------

select id as claimed_id from claim_outbox_batch(10) where dedupe_key = 'test:invite:1' \gset
select ok(:'claimed_id' is not null, 'claim_outbox_batch() claims the pending row');
select is(
  (select status::text from email_outbox where id = :'claimed_id'),
  'sending',
  'a claimed row moves to sending'
);
select is(
  (select count(*)::int from claim_outbox_batch(10)),
  0,
  'a row already claimed is not claimed again'
);

select mark_outbox_sent(:'claimed_id'::uuid, 'resend-msg-1');
select is(
  (select status::text from email_outbox where id = :'claimed_id'),
  'sent',
  'mark_outbox_sent() marks the row sent and records the provider id'
);

-- A fresh row: fail it once, expect a retryable pending state with backoff.
select enqueue_email(
  'test:fail:1', null, 'fails@example.com', 'group_invitation', '{}'::jsonb, :'group_a_id'::uuid
);
select id as fail_id from claim_outbox_batch(10) where dedupe_key = 'test:fail:1' \gset
select mark_outbox_failed(:'fail_id'::uuid, 'temporary provider error');
select is(
  (select status::text from email_outbox where id = :'fail_id'),
  'pending',
  'a failure below max_attempts is scheduled to retry'
);
select ok(
  (select next_attempt_at > now() from email_outbox where id = :'fail_id'),
  'the retry is backed off into the future'
);

-- Exhaust retries directly (bypassing the normal claim loop, since this
-- test isn't waiting out real backoff delays) and confirm permanent failure.
update email_outbox set attempts = max_attempts where id = :'fail_id';
select mark_outbox_failed(:'fail_id'::uuid, 'permanent provider error');
select is(
  (select status::text from email_outbox where id = :'fail_id'),
  'failed',
  'exhausting max_attempts marks the row permanently failed'
);

-- ---------------------------------------------------------------------
-- record_email_delivery_event(): bounce suppresses future mail
-- ---------------------------------------------------------------------

select enqueue_email(
  'test:bounce:1', :'dave_uid'::uuid, 'dave@example.com', 'group_invitation', '{}'::jsonb, :'group_b_id'::uuid
);
select id as bounce_id from claim_outbox_batch(10) where dedupe_key = 'test:bounce:1' \gset
select mark_outbox_sent(:'bounce_id'::uuid, 'resend-msg-bounce');
select record_email_delivery_event('resend-msg-bounce', 'bounced');
select is(
  (select bounced_at is not null from email_outbox where id = :'bounce_id'),
  true,
  'a bounce event is recorded on the outbox row'
);
select is(
  (select suppressed from email_preferences where user_id = :'dave_uid'),
  true,
  'a hard bounce suppresses all future mail to that recipient'
);

-- ---------------------------------------------------------------------
-- unsubscribe_by_token(): works signed out, only touches opt-in flags
-- ---------------------------------------------------------------------

select unsubscribe_token as bob_unsub_token from email_preferences where user_id = :'bob_uid' \gset

select tests.clear_authentication();

select lives_ok(
  format('select unsubscribe_by_token(%L, %L)', :'bob_unsub_token', 'announcements'),
  'unsubscribing works while signed out, given a valid token'
);
select is(
  (select announcements_enabled from email_preferences where user_id = :'bob_uid'),
  false,
  'the targeted category was turned off'
);
select is(
  (select suppressed from email_preferences where user_id = :'bob_uid'),
  false,
  'unsubscribing from one category does not suppress all mail'
);
select throws_ok(
  $$select unsubscribe_by_token('00000000-0000-0000-0000-000000000000'::uuid, 'reminders')$$,
  'P0002',
  'This unsubscribe link is no longer valid.',
  'an unrecognized token is rejected'
);

-- ---------------------------------------------------------------------
-- get_group_email_activity(): organizer-only dashboard
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'bob_uid');
select throws_ok(
  format('select * from get_group_email_activity(%L)', :'group_a_id'),
  '42501',
  'Only an organizer can view email activity.',
  'a plain member cannot view the group''s email activity'
);

select tests.authenticate_as(:'alice_uid');
select ok(
  (select count(*)::int from get_group_email_activity(:'group_a_id'::uuid)) > 0,
  'the organizer can see a summary of the group''s email activity'
);

-- ---------------------------------------------------------------------
-- scheduler_tick(): drive three cycles into their due states and run
-- one tick. Directly editing timestamps (rather than waiting out real
-- time) requires two statements per cycle: the first sets the
-- business timestamp and lets the recompute trigger fire (it can only
-- fall back to "check again in a day", since every real checkpoint is
-- now in the past); the second, deliberately not touching
-- phase/*_at columns, forces next_action_at into the past so this
-- tick actually picks the row up — exactly what scheduler_tick()
-- itself does at the end of each loop iteration for cycles it only
-- partially handles.
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
select id as cycle_a1_id from start_cycle(:'group_a_id'::uuid) \gset
insert into question_proposals (cycle_id, author_id, text)
values (:'cycle_a1_id'::uuid, :'alice_uid'::uuid, 'What are you proud of this month?')
returning id as proposal_a1_id \gset
select finalize_questions(:'cycle_a1_id'::uuid, array[:'proposal_a1_id'::uuid]);

select tests.authenticate_as(:'carol_uid');
select id as cycle_b1_id from start_cycle(:'group_b_id'::uuid) \gset
insert into question_proposals (cycle_id, author_id, text)
values (:'cycle_b1_id'::uuid, :'carol_uid'::uuid, 'What made you laugh recently?')
returning id as proposal_b1_id \gset
select finalize_questions(:'cycle_b1_id'::uuid, array[:'proposal_b1_id'::uuid]);

select tests.authenticate_as(:'frank_uid');
select id as cycle_f1_id from start_cycle(:'group_f_id'::uuid) \gset

select tests.become_service_role();

-- Group A's cycle: due in the past -> auto-publish + auto-start.
update cycles set answer_due_at = now() - interval '1 hour' where id = :'cycle_a1_id';
update cycles set next_action_at = now() - interval '1 minute' where id = :'cycle_a1_id';

-- Group B's cycle: due soon, inside the 2-day reminder window, but not
-- yet due -> reminders only, no publish.
update cycles set answer_due_at = now() + interval '1 day' where id = :'cycle_b1_id';
update cycles set next_action_at = now() - interval '1 minute' where id = :'cycle_b1_id';

-- Group F: still in question_collection, past its close date -> nudge
-- the organizer instead of auto-advancing.
update cycles set question_closes_at = now() - interval '1 hour' where id = :'cycle_f1_id';
update cycles set next_action_at = now() - interval '1 minute' where id = :'cycle_f1_id';

select cycles_examined from scheduler_tick(50) \gset

select ok(:'cycles_examined'::int >= 3, 'scheduler_tick() examines all three due cycles');

select is(
  (select phase::text from cycles where id = :'cycle_a1_id'),
  'published',
  'a cycle past its answer deadline is auto-published'
);
select is(
  (select count(*)::int from cycles where group_id = :'group_a_id' and sequence_no = 2),
  1,
  'the next cycle is started automatically after auto-publish'
);
select is(
  (select actor_id is null from audit_events
   where group_id = :'group_a_id' and event_type = 'cycle_auto_published'),
  true,
  'the auto-publish audit event has no human actor'
);
select is(
  (select count(*)::int from audit_events
   where group_id = :'group_a_id' and event_type = 'cycle_auto_started'),
  1,
  'the auto-started next cycle is audited too'
);
select ok(
  (select count(*)::int from email_outbox
   where group_id = :'group_a_id' and template = 'issue_published') >= 2,
  'issue_published mail was enqueued for the published cycle''s members'
);
select ok(
  (select count(*)::int from email_outbox
   where group_id = :'group_a_id' and template = 'question_collection_opened'
     and dedupe_key like '%' || (select id::text from cycles where group_id = :'group_a_id' and sequence_no = 2) || '%'
  ) >= 2,
  'question_collection_opened mail was enqueued for the new cycle''s members'
);

select is(
  (select phase::text from cycles where id = :'cycle_b1_id'),
  'answering',
  'a cycle not yet past its deadline is left open by the scheduler'
);
select ok(
  (select count(*)::int from email_outbox
   where group_id = :'group_b_id' and template = 'answer_deadline_reminder') >= 2,
  'a deadline reminder was enqueued for members who have not submitted'
);

select is(
  (select phase::text from cycles where id = :'cycle_f1_id'),
  'question_collection',
  'automatic question selection is out of scope: an overdue question phase is not auto-advanced'
);
select ok(
  (select count(*)::int from email_outbox
   where group_id = :'group_f_id' and template = 'question_phase_overdue') = 1,
  'the organizer is nudged once about the overdue question phase'
);

-- Re-running the tick should not duplicate any of the above mail.
select count(*)::int as issue_published_count_before
  from email_outbox where group_id = :'group_a_id' and template = 'issue_published' \gset

select scheduler_tick(50);

select is(
  (select count(*)::int from email_outbox
   where group_id = :'group_a_id' and template = 'issue_published'),
  :'issue_published_count_before'::int,
  'rerunning the tick does not duplicate issue_published mail'
);
select ok(
  (select count(*)::int from email_outbox
   where group_id = :'group_f_id' and template = 'question_phase_overdue') = 1,
  'rerunning the tick on the same day does not send a second overdue nudge'
);

-- ---------------------------------------------------------------------
-- get_operational_health(): service-role only, aggregate counts
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
select throws_ok(
  'select * from get_operational_health()',
  '42501',
  'permission denied for function get_operational_health',
  'a regular authenticated user cannot read operational health'
);

select tests.become_service_role();
select ok(
  (select last_scheduler_run_at is not null from get_operational_health()),
  'get_operational_health() reports the last scheduler run once one has completed'
);

select * from finish();
rollback;
