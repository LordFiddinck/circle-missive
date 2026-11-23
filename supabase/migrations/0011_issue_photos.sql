-- 0011: photos with captions on each issue.
--
-- Members can attach up to 5 photos to a cycle while it is open for
-- answers, each with a caption. The photos are shared with the group
-- when the issue is published, exactly like answers.
--
-- Two pieces, kept deliberately parallel:
--   * `issue_photos`  — one row per photo (who, which cycle, caption,
--                       size, where the file lives). This is the single
--                       source of truth for who may see a photo.
--   * the private `issue-photos` Storage bucket — the files themselves.
--                       Its access rules defer to `issue_photos`, so the
--                       file and its row can never disagree about who
--                       may see them.
--
-- Visibility (the same rules as answers):
--   * the author sees their own photos at any time;
--   * other group members see them only once the cycle is published;
--   * a pair hidden from each other (0010) never sees each other's
--     photos — the check is the same function used for answers.
--
-- The browser shrinks every photo and re-encodes it as a JPEG before
-- upload, which also strips embedded location data. The bucket only
-- accepts JPEGs up to 2 MB as a backstop.

-- ---------------------------------------------------------------------
-- 1. The table
-- ---------------------------------------------------------------------

create table issue_photos (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references cycles (id) on delete cascade,
  author_id uuid not null references profiles (user_id) on delete cascade,
  storage_path text not null unique,
  caption text not null default '',
  width int not null check (width between 1 and 10000),
  height int not null check (height between 1 and 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint issue_photos_caption_length check (char_length(caption) <= 500),
  -- The file's location is derived from its own ids, so a row can never
  -- point at someone else's file.
  constraint issue_photos_path_shape check (
    storage_path = cycle_id::text || '/' || author_id::text || '/' || id::text || '.jpg'
  )
);

create index issue_photos_cycle_idx on issue_photos (cycle_id, created_at);

create trigger issue_photos_set_updated_at
  before update on issue_photos
  for each row execute procedure set_updated_at();

-- Only the caption may be edited after upload.
create function guard_issue_photo_update()
returns trigger
language plpgsql
as $$
begin
  if new.id <> old.id
     or new.cycle_id <> old.cycle_id
     or new.author_id <> old.author_id
     or new.storage_path <> old.storage_path
     or new.width <> old.width
     or new.height <> old.height then
    raise exception 'Only the caption can be edited.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger issue_photos_guard_update
  before update on issue_photos
  for each row execute procedure guard_issue_photo_update();

-- At most 5 photos per member per cycle. The advisory lock makes two
-- uploads racing each other count one after the other.
create function enforce_issue_photo_limit()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_count int;
begin
  perform pg_advisory_xact_lock(
    hashtextextended(new.cycle_id::text || ':' || new.author_id::text, 0)
  );

  select count(*) into v_count
  from issue_photos
  where cycle_id = new.cycle_id and author_id = new.author_id;

  if v_count >= 5 then
    raise exception 'You can add up to 5 photos per issue.' using errcode = '22023';
  end if;

  return new;
end;
$$;

create trigger issue_photos_limit
  before insert on issue_photos
  for each row execute procedure enforce_issue_photo_limit();

-- ---------------------------------------------------------------------
-- 2. Row-level security
-- ---------------------------------------------------------------------

alter table issue_photos enable row level security;

create policy "issue_photos_select"
  on issue_photos for select
  using (
    exists (
      select 1 from cycles c
      where c.id = issue_photos.cycle_id
        and is_group_member(c.group_id, auth.uid())
        and (
          issue_photos.author_id = auth.uid()
          or (
            c.phase = 'published'
            and not is_answer_hidden_from_me(c.group_id, issue_photos.author_id)
          )
        )
    )
  );

create policy "issue_photos_insert_own"
  on issue_photos for insert
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from cycles c
      where c.id = issue_photos.cycle_id
        and c.phase = 'answering'
        and is_group_member(c.group_id, auth.uid())
    )
  );

create policy "issue_photos_update_own"
  on issue_photos for update
  using (
    author_id = auth.uid()
    and exists (
      select 1 from cycles c
      where c.id = issue_photos.cycle_id and c.phase = 'answering'
    )
  )
  with check (author_id = auth.uid());

-- An author can remove their own photo while answering is open; an
-- organizer can remove any photo they can see (so, after publication).
create policy "issue_photos_delete"
  on issue_photos for delete
  using (
    exists (
      select 1 from cycles c
      where c.id = issue_photos.cycle_id
        and (
          (
            issue_photos.author_id = auth.uid()
            and c.phase = 'answering'
            and is_group_member(c.group_id, auth.uid())
          )
          or is_group_organizer(c.group_id, auth.uid())
        )
    )
  );

revoke all on issue_photos from public, anon, authenticated;
grant select, insert, update, delete on issue_photos to authenticated;

-- ---------------------------------------------------------------------
-- 3. The Storage bucket and its access rules
--
-- Files live at  <cycle_id>/<author_id>/<photo_id>.jpg  inside a
-- private bucket. Storage's own row-level security guards
-- `storage.objects`; these policies mirror the table rules above.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('issue-photos', 'issue-photos', false, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

-- May the signed-in user create a file at this path? Only in their own
-- folder, for a cycle of their group that is open for answers.
create function can_upload_issue_photo(p_name text)
returns boolean
language plpgsql
stable
security definer set search_path = public
as $$
declare
  v_group_id uuid;
begin
  if auth.uid() is null
     or p_name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
     or split_part(p_name, '/', 2)::uuid <> auth.uid() then
    return false;
  end if;

  select c.group_id into v_group_id
  from cycles c
  where c.id = split_part(p_name, '/', 1)::uuid and c.phase = 'answering';

  return v_group_id is not null and is_group_member(v_group_id, auth.uid());
end;
$$;

-- May the signed-in user delete the file at this path? Its author while
-- answering is open, or an organizer of the group at any time.
create function can_delete_issue_photo(p_name text)
returns boolean
language plpgsql
stable
security definer set search_path = public
as $$
declare
  v_group_id uuid;
  v_phase text;
begin
  if auth.uid() is null
     or p_name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$' then
    return false;
  end if;

  select c.group_id, c.phase::text into v_group_id, v_phase
  from cycles c
  where c.id = split_part(p_name, '/', 1)::uuid;

  if v_group_id is null then
    return false;
  end if;

  return is_group_organizer(v_group_id, auth.uid())
    or (
      split_part(p_name, '/', 2)::uuid = auth.uid()
      and v_phase = 'answering'
      and is_group_member(v_group_id, auth.uid())
    );
end;
$$;

-- Reading: a member's own folder at any time (so they can preview and
-- clean up their own uploads), or any file that has a photo row the
-- signed-in user is allowed to see. That subquery runs under the
-- invoker's row-level security, so the visibility rules — publication,
-- group membership, hidden pairs — live in exactly one place.
create policy "issue_photos_objects_select"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'issue-photos'
    and (
      (storage.foldername(name))[2] = auth.uid()::text
      or exists (
        select 1 from public.issue_photos p where p.storage_path = storage.objects.name
      )
    )
  );

create policy "issue_photos_objects_insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'issue-photos'
    and public.can_upload_issue_photo(name)
  );

create policy "issue_photos_objects_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'issue-photos'
    and public.can_delete_issue_photo(name)
  );

-- Deliberately no UPDATE policy: a photo file is never overwritten.
