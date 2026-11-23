begin;
create extension if not exists pgtap;

select plan(47);

-- ---------------------------------------------------------------------
-- Fixtures
--   Group G: Alice (organizer), Bob, Carol, Dave. Cycle is released
--   (answering). Eve belongs to no group.
-- ---------------------------------------------------------------------

select tests.create_user('alice@example.com') as uid \gset alice_
select tests.create_user('bob@example.com')   as uid \gset bob_
select tests.create_user('carol@example.com') as uid \gset carol_
select tests.create_user('dave@example.com')  as uid \gset dave_
select tests.create_user('eve@example.com')   as uid \gset eve_

-- ---------------------------------------------------------------------
-- The bucket
-- ---------------------------------------------------------------------

select is(
  (select public from storage.buckets where id = 'issue-photos'),
  false,
  'the photo bucket is private'
);
select is(
  (select file_size_limit from storage.buckets where id = 'issue-photos'),
  2097152::bigint,
  'the photo bucket caps files at 2 MB'
);
select is(
  (select allowed_mime_types from storage.buckets where id = 'issue-photos'),
  array['image/jpeg'],
  'the photo bucket accepts only JPEGs'
);

select tests.authenticate_as(:'alice_uid');
select id as group_id from create_group('Group G', 'UTC', 28, 1, 1) \gset
select token as t_bob   from create_invitation(:'group_id'::uuid, 'bob@example.com')   \gset
select token as t_carol from create_invitation(:'group_id'::uuid, 'carol@example.com') \gset
select token as t_dave  from create_invitation(:'group_id'::uuid, 'dave@example.com')  \gset
select tests.authenticate_as(:'bob_uid');
select accept_invitation(:'t_bob');
select tests.authenticate_as(:'carol_uid');
select accept_invitation(:'t_carol');
select tests.authenticate_as(:'dave_uid');
select accept_invitation(:'t_dave');

select tests.authenticate_as(:'alice_uid');
select id as cycle_id from start_cycle(:'group_id'::uuid) \gset
insert into question_proposals (cycle_id, author_id, text)
values (:'cycle_id'::uuid, :'alice_uid'::uuid, 'A question');
select release_questions(:'cycle_id'::uuid);

select gen_random_uuid() as ph_bob  \gset
select gen_random_uuid() as ph_carol \gset
select gen_random_uuid() as ph_dave \gset
select :'cycle_id' || '/' || :'bob_uid'   || '/' || :'ph_bob'   || '.jpg' as path_bob   \gset
select :'cycle_id' || '/' || :'carol_uid' || '/' || :'ph_carol' || '.jpg' as path_carol \gset
select :'cycle_id' || '/' || :'dave_uid'  || '/' || :'ph_dave'  || '.jpg' as path_dave  \gset

-- ---------------------------------------------------------------------
-- Adding photos (rows)
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'bob_uid');
select lives_ok(
  format($f$insert into issue_photos (id, cycle_id, author_id, storage_path, caption, width, height)
            values (%L, %L, %L, %L, 'Bob at the lake', 1600, 1200)$f$,
         :'ph_bob', :'cycle_id', :'bob_uid', :'path_bob'),
  'a member can add a photo while answering is open'
);

select throws_ok(
  format($f$insert into issue_photos (cycle_id, author_id, storage_path, width, height)
            values (%L, %L, 'somewhere/else.jpg', 100, 100)$f$,
         :'cycle_id', :'bob_uid'),
  '23514',
  null,
  'a photo row must point at its own derived file path'
);

select throws_ok(
  format($f$insert into issue_photos (id, cycle_id, author_id, storage_path, width, height)
            values (%L, %L, %L, %L, 100, 100)$f$,
         :'ph_carol', :'cycle_id', :'carol_uid', :'path_carol'),
  '42501',
  null,
  'a member cannot add a photo in someone else''s name'
);

select gen_random_uuid() as ph_cap \gset
select throws_ok(
  format($f$insert into issue_photos (id, cycle_id, author_id, storage_path, caption, width, height)
            values (%L, %L, %L, %L, %L, 100, 100)$f$,
         :'ph_cap', :'cycle_id', :'bob_uid',
         :'cycle_id' || '/' || :'bob_uid' || '/' || :'ph_cap' || '.jpg', repeat('a', 501)),
  '23514',
  'new row for relation "issue_photos" violates check constraint "issue_photos_caption_length"',
  'a caption over 500 characters is rejected'
);

select tests.authenticate_as(:'eve_uid');
select gen_random_uuid() as ph_eve \gset
select throws_ok(
  format($f$insert into issue_photos (id, cycle_id, author_id, storage_path, width, height)
            values (%L, %L, %L, %L, 100, 100)$f$,
         :'ph_eve', :'cycle_id', :'eve_uid',
         :'cycle_id' || '/' || :'eve_uid' || '/' || :'ph_eve' || '.jpg'),
  '42501',
  null,
  'someone outside the group cannot add a photo'
);

-- The limit: 5 per member per cycle.
select tests.authenticate_as(:'bob_uid');
with ids as (select gen_random_uuid() as id from generate_series(1, 4))
insert into issue_photos (id, cycle_id, author_id, storage_path, width, height)
select id, :'cycle_id'::uuid, :'bob_uid'::uuid,
       :'cycle_id' || '/' || :'bob_uid' || '/' || id || '.jpg', 800, 600
from ids;

select is(
  (select count(*)::int from issue_photos where author_id = :'bob_uid'),
  5,
  'a member can have 5 photos on one issue'
);

select throws_ok(
  format($f$insert into issue_photos (id, cycle_id, author_id, storage_path, width, height)
            values (%L, %L, %L, %L, 100, 100)$f$,
         :'ph_dave', :'cycle_id', :'bob_uid',
         :'cycle_id' || '/' || :'bob_uid' || '/' || :'ph_dave' || '.jpg'),
  '22023',
  'You can add up to 5 photos per issue.',
  'a sixth photo is refused'
);

select tests.authenticate_as(:'carol_uid');
select lives_ok(
  format($f$insert into issue_photos (id, cycle_id, author_id, storage_path, caption, width, height)
            values (%L, %L, %L, %L, 'Carol''s cat', 1200, 1600)$f$,
         :'ph_carol', :'cycle_id', :'carol_uid', :'path_carol'),
  'the limit is per member: another member can still add a photo'
);

-- ---------------------------------------------------------------------
-- Before publication: private to the author
-- ---------------------------------------------------------------------

select is(
  (select count(*)::int from issue_photos),
  1,
  'before publication a member sees only their own photos'
);

select tests.authenticate_as(:'alice_uid');
select is(
  (select count(*)::int from issue_photos),
  0,
  'before publication even an organizer sees no one else''s photos'
);

select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from issue_photos where author_id = :'bob_uid'),
  5,
  'the author still sees all of their own photos'
);

-- ---------------------------------------------------------------------
-- Editing and removing while answering is open
-- ---------------------------------------------------------------------

update issue_photos set caption = 'Bob at the lake, sunrise' where id = :'ph_bob';
select is(
  (select caption from issue_photos where id = :'ph_bob'),
  'Bob at the lake, sunrise',
  'an author can edit their own caption'
);

select throws_ok(
  format('update issue_photos set storage_path = %L where id = %L', 'a/b/c.jpg', :'ph_bob'),
  '42501',
  'Only the caption can be edited.',
  'nothing but the caption can be changed'
);

select tests.authenticate_as(:'carol_uid');
update issue_photos set caption = 'hijacked' where id = :'ph_bob';
select tests.authenticate_as(:'bob_uid');
select is(
  (select caption from issue_photos where id = :'ph_bob'),
  'Bob at the lake, sunrise',
  'a member cannot edit someone else''s caption'
);

select tests.authenticate_as(:'carol_uid');
with d as (delete from issue_photos where id = :'ph_bob' returning 1)
select count(*)::int as n from d \gset del_other_
select is(:del_other_n, 0, 'a member cannot remove someone else''s photo');

-- ---------------------------------------------------------------------
-- Storage objects while answering is open
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'bob_uid');
select lives_ok(
  format($f$insert into storage.objects (bucket_id, name, owner) values ('issue-photos', %L, %L)$f$,
         :'path_bob', :'bob_uid'),
  'a member can upload a file into their own folder'
);

select throws_ok(
  format($f$insert into storage.objects (bucket_id, name, owner) values ('issue-photos', %L, %L)$f$,
         :'path_carol', :'bob_uid'),
  '42501',
  null,
  'a member cannot upload into someone else''s folder'
);

select throws_ok(
  $f$insert into storage.objects (bucket_id, name, owner) values ('issue-photos', 'not-a-valid-path.jpg', null)$f$,
  '42501',
  null,
  'a file at a malformed path is refused'
);

select tests.authenticate_as(:'eve_uid');
select throws_ok(
  format($f$insert into storage.objects (bucket_id, name, owner) values ('issue-photos', %L, %L)$f$,
         :'cycle_id' || '/' || :'eve_uid' || '/' || gen_random_uuid() || '.jpg', :'eve_uid'),
  '42501',
  null,
  'someone outside the group cannot upload'
);

select tests.authenticate_as(:'carol_uid');
select lives_ok(
  format($f$insert into storage.objects (bucket_id, name, owner) values ('issue-photos', %L, %L)$f$,
         :'path_carol', :'carol_uid'),
  'a second member can upload their own file'
);
select is(
  (select count(*)::int from storage.objects where bucket_id = 'issue-photos'),
  1,
  'before publication a member can read only their own file'
);

with d as (delete from storage.objects where name = :'path_bob' returning 1)
select count(*)::int as n from d \gset del_obj_other_
select is(:del_obj_other_n, 0, 'a member cannot delete someone else''s file');

-- ---------------------------------------------------------------------
-- Removing one's own photo (file first, then its row)
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'dave_uid');
select gen_random_uuid() as ph_dave2 \gset
select :'cycle_id' || '/' || :'dave_uid' || '/' || :'ph_dave2' || '.jpg' as path_dave2 \gset
insert into issue_photos (id, cycle_id, author_id, storage_path, width, height)
values (:'ph_dave2', :'cycle_id', :'dave_uid', :'path_dave2', 640, 480);
insert into storage.objects (bucket_id, name, owner) values ('issue-photos', :'path_dave2', :'dave_uid');

with d as (delete from storage.objects where name = :'path_dave2' returning 1)
select count(*)::int as n from d \gset del_own_obj_
select is(:del_own_obj_n, 1, 'an author can delete their own file while answering is open');

with d as (delete from issue_photos where id = :'ph_dave2' returning 1)
select count(*)::int as n from d \gset del_own_row_
select is(:del_own_row_n, 1, 'an author can remove their own photo while answering is open');

-- ---------------------------------------------------------------------
-- After publication
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
select publish_cycle(:'cycle_id'::uuid);

select tests.authenticate_as(:'carol_uid');
select is(
  (select count(*)::int from issue_photos),
  6,
  'after publication a member sees everyone''s photos (Bob''s 5 and their own)'
);
select is(
  (select count(*)::int from storage.objects where bucket_id = 'issue-photos'),
  2,
  'after publication a member can read the files behind those photos'
);

select tests.authenticate_as(:'eve_uid');
select is(
  (select count(*)::int from issue_photos),
  0,
  'someone outside the group sees no photos'
);
select is(
  (select count(*)::int from storage.objects where bucket_id = 'issue-photos'),
  0,
  'someone outside the group sees no files'
);

select tests.authenticate_as(:'bob_uid');
update issue_photos set caption = 'too late' where id = :'ph_bob';
select is(
  (select caption from issue_photos where id = :'ph_bob'),
  'Bob at the lake, sunrise',
  'captions cannot be edited after publication'
);
with d as (delete from issue_photos where id = :'ph_bob' returning 1)
select count(*)::int as n from d \gset del_late_
select is(:del_late_n, 0, 'an author cannot remove a photo after publication');

select tests.authenticate_as(:'carol_uid');
select gen_random_uuid() as ph_late \gset
select throws_ok(
  format($f$insert into issue_photos (id, cycle_id, author_id, storage_path, width, height)
            values (%L, %L, %L, %L, 100, 100)$f$,
         :'ph_late', :'cycle_id', :'carol_uid',
         :'cycle_id' || '/' || :'carol_uid' || '/' || :'ph_late' || '.jpg'),
  '42501',
  null,
  'no photo can be added after publication'
);
select throws_ok(
  format($f$insert into storage.objects (bucket_id, name, owner) values ('issue-photos', %L, %L)$f$,
         :'cycle_id' || '/' || :'carol_uid' || '/' || gen_random_uuid() || '.jpg', :'carol_uid'),
  '42501',
  null,
  'no file can be uploaded after publication'
);

-- ---------------------------------------------------------------------
-- Hidden pairs apply to photos too
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
select hide_answers_between(:'group_id'::uuid, :'bob_uid'::uuid, :'carol_uid'::uuid);

select tests.authenticate_as(:'carol_uid');
select is(
  (select count(*)::int from issue_photos where author_id = :'bob_uid'),
  0,
  'a hidden pair cannot see each other''s photos'
);
select is(
  (select count(*)::int from storage.objects where name = :'path_bob'),
  0,
  'a hidden pair cannot read each other''s files either'
);
select is(
  (select count(*)::int from issue_photos where author_id = :'carol_uid'),
  1,
  'a member still sees their own photos'
);

select tests.authenticate_as(:'bob_uid');
select is(
  (select count(*)::int from issue_photos where author_id = :'carol_uid'),
  0,
  'the block is symmetric for photos'
);

select tests.authenticate_as(:'dave_uid');
select is(
  (select count(*)::int from issue_photos),
  6,
  'members outside the pair still see every photo'
);

-- ---------------------------------------------------------------------
-- Organizers can remove photos they can see
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
with d as (delete from storage.objects where name = :'path_bob' returning 1)
select count(*)::int as n from d \gset org_obj_
select is(:org_obj_n, 1, 'an organizer can delete a published photo''s file');

with d as (delete from issue_photos where id = :'ph_bob' returning 1)
select count(*)::int as n from d \gset org_row_
select is(:org_row_n, 1, 'an organizer can remove a published photo');

-- An organizer who is hidden from an author cannot see (so cannot
-- remove) that author's photos. Another organizer can.
select hide_answers_between(:'group_id'::uuid, :'alice_uid'::uuid, :'carol_uid'::uuid);
with d as (delete from issue_photos where id = :'ph_carol' returning 1)
select count(*)::int as n from d \gset org_hidden_
select is(:org_hidden_n, 0, 'an organizer hidden from an author cannot remove their photo');

select restore_answers_between(:'group_id'::uuid, :'alice_uid'::uuid, :'carol_uid'::uuid);
with d as (delete from issue_photos where id = :'ph_carol' returning 1)
select count(*)::int as n from d \gset org_restored_
select is(:org_restored_n, 1, 'once restored, the organizer can remove it');

-- ---------------------------------------------------------------------
-- Photos do not leak between cycles' phases: a skipped cycle stays dark
-- ---------------------------------------------------------------------

select tests.authenticate_as(:'alice_uid');
select id as cycle2_id from start_cycle(:'group_id'::uuid) \gset
select tests.authenticate_as(:'bob_uid');
select gen_random_uuid() as ph_early \gset
select throws_ok(
  format($f$insert into issue_photos (id, cycle_id, author_id, storage_path, width, height)
            values (%L, %L, %L, %L, 100, 100)$f$,
         :'ph_early', :'cycle2_id', :'bob_uid',
         :'cycle2_id' || '/' || :'bob_uid' || '/' || :'ph_early' || '.jpg'),
  '42501',
  null,
  'photos cannot be added while questions are still being collected'
);

select is(
  (select count(*)::int from pg_policies where tablename = 'objects' and schemaname = 'storage'
     and policyname like 'issue_photos_objects_%' and cmd = 'UPDATE'),
  0,
  'there is no update policy, so a photo file can never be overwritten'
);

select is(
  has_table_privilege('anon', 'public.issue_photos', 'select'),
  false,
  'the anonymous role has no access to photo rows'
);

select * from finish();
rollback;
