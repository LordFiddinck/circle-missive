-- Local pgTAP harness only.
--
-- A real Supabase project bootstraps `alter default privileges ... grant
-- all on tables in schema public to anon, authenticated, service_role`
-- once, automatically, when the project is created — so migrations
-- don't need to (and don't) grant table privileges for `profiles`
-- themselves. Plain Postgres has no such bootstrap, so we do the
-- equivalent here, scoped to exactly what phase 1's `profiles` RLS
-- policies expect the `authenticated` role to be able to attempt.
grant select, update on profiles to authenticated;
grant select on profiles to anon;

-- Note: 0003_cycles_questions_answers.sql grants its own tables
-- directly at the bottom of the migration (the same way 0002 does for
-- groups/memberships/invitations), so nothing needs to be added here
-- for cycles/questions/answers — only `profiles`, from 0001, which
-- predates that convention, needs a stand-in for Supabase's automatic
-- bootstrap grant.

-- `service_role` is new as of Phase 4. Its `bypassrls` attribute (see
-- 000_stub_auth.sql) only bypasses row level security — it says
-- nothing about ordinary table grants, which are a separate system.
-- Every Phase 4 SECURITY DEFINER function (enqueue_email(),
-- scheduler_tick(), etc.) runs as its *owner*, not its caller, so
-- those don't need this. But 0004's own pgTAP test drives the
-- scheduler by editing cycle/outbox rows directly as service_role
-- (simulating time passing, rather than waiting for it), which does
-- need real table privileges — exactly the bootstrap grant a real
-- Supabase project already gives service_role automatically.
grant all on all tables in schema public to service_role;
