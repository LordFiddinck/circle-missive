-- Patches a bug in 0004_scheduling_email.sql's trigger, for any
-- environment where that migration already ran in its original form
-- before the bug was found. `create or replace function` is safe to
-- run whether or not the target already has this exact fixed version
-- (a fresh `supabase db reset`/`db push` gets it straight from the now
-- -corrected 0004, and this migration then just redefines the same
-- thing again — a harmless no-op).
--
-- The bug: prevent_email_preferences_privileged_change() unconditionally
-- blocked any change to `suppressed`, including from
-- record_email_delivery_event() itself — the one legitimate,
-- `security definer` codepath that's supposed to suppress a user after
-- a real bounce/complaint. `security definer` bypasses RLS and grants,
-- but never bypasses a table trigger, so that internal call was being
-- rejected by its own safety net. See 0004_scheduling_email.sql's
-- current (corrected) version of both functions for the full
-- explanation — this migration exists only to bring an
-- already-migrated database in line with that fix.

create or replace function prevent_email_preferences_privileged_change()
returns trigger
language plpgsql
as $$
begin
  if new.suppressed <> old.suppressed
     and coalesce(current_setting('circle_missive.allow_suppressed_change', true), '') <> 'on' then
    raise exception 'email_preferences.suppressed cannot be set directly.';
  end if;
  if new.unsubscribe_token <> old.unsubscribe_token then
    raise exception 'email_preferences.unsubscribe_token is immutable.';
  end if;
  return new;
end;
$$;

create or replace function record_email_delivery_event(
  p_provider_message_id text,
  p_event_type text,
  p_occurred_at timestamptz default now()
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_row email_outbox%rowtype;
begin
  select * into v_row from email_outbox where provider_message_id = p_provider_message_id;
  if v_row.id is null then
    return; -- unrecognized message id (e.g. a provider test event) — nothing to reconcile
  end if;

  if p_event_type = 'delivered' then
    update email_outbox set delivered_at = p_occurred_at
    where id = v_row.id and delivered_at is null;

  elsif p_event_type = 'bounced' then
    update email_outbox set bounced_at = p_occurred_at
    where id = v_row.id and bounced_at is null;
    if v_row.recipient_user_id is not null then
      perform set_config('circle_missive.allow_suppressed_change', 'on', true);
      update email_preferences set suppressed = true, updated_at = now()
      where user_id = v_row.recipient_user_id;
      perform set_config('circle_missive.allow_suppressed_change', 'off', true);
    end if;

  elsif p_event_type = 'complained' then
    update email_outbox set complained_at = p_occurred_at
    where id = v_row.id and complained_at is null;
    if v_row.recipient_user_id is not null then
      perform set_config('circle_missive.allow_suppressed_change', 'on', true);
      update email_preferences set suppressed = true, updated_at = now()
      where user_id = v_row.recipient_user_id;
      perform set_config('circle_missive.allow_suppressed_change', 'off', true);
    end if;
  end if;
end;
$$;

-- create or replace function preserves existing grants in Postgres, so
-- the revoke/grant pair from 0004 doesn't need repeating here — but
-- stated explicitly anyway, since "preserves grants" is easy to get
-- wrong and cheap to just re-assert.
revoke execute on function record_email_delivery_event(text, text, timestamptz) from public;
grant execute on function record_email_delivery_event(text, text, timestamptz) to service_role;
