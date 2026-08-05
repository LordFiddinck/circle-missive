-- Phase 1: project foundation
-- Creates `profiles`, one row per authenticated user, kept in sync with
-- auth.users via a trigger. Every other table in later migrations
-- references profiles(user_id) rather than auth.users directly, keeping
-- the auth schema untouched by application logic.

create table profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  locale text not null default 'en',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table profiles enable row level security;

-- A signed-in user may read and update only their own profile row.
-- There is no "browse other users" policy: profile visibility beyond
-- the owner is scoped through group membership in later migrations.
create policy "profiles_select_own"
  on profiles for select
  using (auth.uid() = user_id);

create policy "profiles_update_own"
  on profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Automatically create a profile row whenever a new auth user is created,
-- so the frontend never has to perform a separate "create my profile" step.
create function handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- Keep `updated_at` current on every profile edit.
create function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on profiles
  for each row execute procedure set_updated_at();
