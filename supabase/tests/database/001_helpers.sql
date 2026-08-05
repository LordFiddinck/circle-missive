-- Shared pgTAP test helpers.
--
-- `tests.create_user` inserts a fake auth user (and relies on the
-- profiles-sync trigger from 0001_init_profiles.sql to create their
-- profile row, exactly as it would for a real signed-up user).
-- `tests.authenticate_as` makes subsequent statements in the same
-- transaction run as that user, the same way PostgREST sets
-- `request.jwt.claim.sub` from the caller's access token.

create schema if not exists tests;

create or replace function tests.create_user(p_email text)
returns uuid
language plpgsql
as $$
declare
  v_user_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, email)
  values (v_user_id, p_email);
  return v_user_id;
end;
$$;

create or replace function tests.authenticate_as(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function tests.clear_authentication()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('role', 'anon', true);
end;
$$;

-- Phase 4 adds functions granted only to `service_role` (the scheduler
-- and email-worker Edge Functions never run as `authenticated`). This
-- switches the test session's effective role the same way
-- authenticate_as() does for a normal user, without a JWT subject.
create or replace function tests.become_service_role()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('role', 'service_role', true);
end;
$$;

grant usage on schema tests to anon, authenticated, service_role;
grant execute on function tests.authenticate_as(uuid) to anon, authenticated, service_role;
grant execute on function tests.clear_authentication() to anon, authenticated, service_role;
grant execute on function tests.become_service_role() to anon, authenticated, service_role;
