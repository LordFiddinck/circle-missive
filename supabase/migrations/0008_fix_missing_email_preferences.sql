-- Phase 6c: fix regression introduced by 0006_default_display_name.sql
--
--   0006 rewrote handle_new_user() based on 0001's original version,
--   which only inserted a profiles row. But 0004_scheduling_email.sql
--   had already extended handle_new_user() to *also* insert an
--   email_preferences row for every new signup. 0006's
--   `create or replace function` silently dropped that second insert.
--
--   Net effect: every user who signed up between 0006 being applied
--   and this migration has no email_preferences row at all — no
--   unsubscribe_token, no announcements_enabled default, and any code
--   expecting that row (enqueue_email(), the dashboard's email
--   preferences section, the pgTAP fixtures) breaks for them. Restore
--   both inserts, and backfill anyone who fell through the gap.

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      split_part(new.email, '@', 1)
    )
  );

  insert into public.email_preferences (user_id)
  values (new.id);

  return new;
end;
$$;

-- Backfill: anyone whose signup fell in the gap between 0006 and this
-- migration has a profile but no email_preferences row.
insert into email_preferences (user_id)
select p.user_id
from profiles p
left join email_preferences ep on ep.user_id = p.user_id
where ep.user_id is null;
