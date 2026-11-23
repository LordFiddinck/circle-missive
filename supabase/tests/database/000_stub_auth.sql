-- Local pgTAP harness only — NOT a migration, and never runs against a
-- real Supabase project.
--
-- `supabase test db` runs these files against a full local Supabase
-- stack, which already has a real `auth` schema, `auth.uid()`, and the
-- `anon`/`authenticated`/`service_role` roles. Plain CI Postgres (see
-- check.yml) and this sandbox don't have that stack, only vanilla
-- Postgres — so this file recreates the minimal slice of it that our
-- RLS policies and functions depend on, guarded so it's a silent no-op
-- if the real `auth` schema already exists.
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'auth') then
    create schema auth;

    create table auth.users (
      id uuid primary key default gen_random_uuid(),
      email text unique not null,
      raw_user_meta_data jsonb not null default '{}'::jsonb,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );

    create function auth.uid() returns uuid
    language sql stable
    as $fn$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
    $fn$;

    create function auth.role() returns text
    language sql stable
    as $fn$
      select coalesce(current_setting('request.jwt.claim.role', true), 'anon');
    $fn$;

    -- Real Supabase installs a trigger that mirrors the one in
    -- 0001_init_profiles.sql; this stub just needs the roles to exist
    -- so `grant ... to authenticated` in migrations succeeds.
    if not exists (select 1 from pg_roles where rolname = 'anon') then
      create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
      create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
      create role service_role nologin bypassrls;
    end if;

    grant usage on schema public to anon, authenticated;
    grant usage on schema auth to anon, authenticated;
  end if;
end;
$$;

-- Same idea for Supabase Storage (needed from 0011_issue_photos.sql
-- on): a minimal `storage` schema — buckets, objects with row-level
-- security enabled, and the `foldername()` helper that Storage policies
-- use — so migrations that create a bucket and policies on
-- `storage.objects` apply on plain Postgres. Silent no-op against a real
-- Supabase stack, which already has all of this.
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'storage') then
    create schema storage;

    create table storage.buckets (
      id text primary key,
      name text not null,
      public boolean not null default false,
      file_size_limit bigint,
      allowed_mime_types text[],
      created_at timestamptz not null default now()
    );

    create table storage.objects (
      id uuid primary key default gen_random_uuid(),
      bucket_id text references storage.buckets (id),
      name text,
      owner uuid,
      created_at timestamptz not null default now(),
      unique (bucket_id, name)
    );

    alter table storage.objects enable row level security;

    -- Same logic as Supabase's own storage.foldername(): every path
    -- segment except the file name.
    create function storage.foldername(name text) returns text[]
    language plpgsql
    as $fn$
    declare
      _parts text[];
    begin
      select string_to_array(name, '/') into _parts;
      return _parts[1:array_length(_parts, 1) - 1];
    end
    $fn$;

    grant usage on schema storage to anon, authenticated;
    grant select, insert, update, delete on storage.objects to authenticated;
  end if;
end;
$$;
