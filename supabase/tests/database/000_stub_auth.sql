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
