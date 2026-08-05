-- Registers the two Supabase Cron jobs that drive Phase 4: one that
-- ticks the scheduler, one that runs the email worker. Not a
-- migration (it doesn't live under supabase/migrations/, and
-- check.yml never applies it) because, unlike everything in this
-- repo's schema, it depends on facts that don't exist until a project
-- is deployed: the project's own Functions URL, and a CRON_SECRET
-- generated for that project. Run this once per environment (a fresh
-- local `supabase start`, staging, production) after functions are
-- deployed, via the SQL Editor or `psql`/`supabase db execute`.
--
-- Prerequisites:
--   1. Deploy the functions: `supabase functions deploy scheduler-tick
--      email-worker email-worker resend-webhook health` (or all of
--      them at once with `supabase functions deploy`).
--   2. Generate a random secret and set it as a project secret:
--        openssl rand -hex 32
--        supabase secrets set CRON_SECRET=<the generated value>
--   3. Replace <project-ref> below with this project's ref (the
--      subdomain of its Supabase URL), and <cron-secret> with the
--      exact value from step 2.
--
-- Supabase Cron uses pg_cron + pg_net under the hood; both extensions
-- are enabled by default on Supabase projects. See:
-- https://supabase.com/docs/guides/cron

select cron.schedule(
  'scheduler-tick',
  '*/10 * * * *', -- every 10 minutes, within the plan's 10-15 minute recommendation (Section 5)
  $$
  select net.http_post(
    url := 'https://<project-ref>.functions.supabase.co/scheduler-tick',
    headers := jsonb_build_object(
      'Authorization', 'Bearer <cron-secret>',
      'Content-Type', 'application/json'
    ),
    timeout_milliseconds := 20000
  );
  $$
);

select cron.schedule(
  'email-worker',
  '*/2 * * * *', -- every 2 minutes, so reminders/notices go out promptly after the scheduler queues them
  $$
  select net.http_post(
    url := 'https://<project-ref>.functions.supabase.co/email-worker',
    headers := jsonb_build_object(
      'Authorization', 'Bearer <cron-secret>',
      'Content-Type', 'application/json'
    ),
    timeout_milliseconds := 20000
  );
  $$
);

-- To inspect scheduled jobs: select * from cron.job;
-- To inspect recent run history: select * from cron.job_run_details order by start_time desc limit 20;
-- To remove a job (e.g. before re-registering with a rotated secret):
--   select cron.unschedule('scheduler-tick');
--   select cron.unschedule('email-worker');
