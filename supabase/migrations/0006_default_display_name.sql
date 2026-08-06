-- Phase 6b: default display_name to the email local-part
--
--   Magic-link sign-in (SignIn.tsx) never sends raw_user_meta_data, so
--   every profile has been landing with display_name = '' (0001's
--   fallback), leaving new members blank until they visit /account.
--   Default to the part of the email before '@' instead, so members
--   show up with *something* readable immediately; they can still
--   change it any time via the account page.

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
  return new;
end;
$$;

-- One-time backfill: anyone who already signed up under the old
-- blank-default behavior (including, likely, your own pilot testers)
-- would otherwise never get this default retroactively.
update profiles p
set display_name = split_part(u.email, '@', 1)
from auth.users u
where u.id = p.user_id
  and p.display_name = '';
