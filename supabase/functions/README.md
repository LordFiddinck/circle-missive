# Edge Functions

These run on Deno via the Supabase CLI, not Node — a separate runtime
from the rest of this repo, which is why they're excluded from the
root `eslint.config.js`/`tsconfig.json` (see the `ignores` comment in
each). Each function's own header comment explains what invokes it and
why it needs `verify_jwt = false` (see `../config.toml`).

| Function          | Invoked by                              | Purpose                                              |
| ------------------ | ---------------------------------------- | ----------------------------------------------------- |
| `scheduler-tick`   | Supabase Cron, every ~10 min             | Advances due cycles, queues reminder/notice mail      |
| `email-worker`     | Supabase Cron, every ~2 min              | Sends queued mail via Resend                          |
| `resend-webhook`   | Resend (delivery/bounce/complaint events) | Records delivery outcomes, suppresses bounced mail    |
| `health`           | An uptime monitor of your choosing        | Reports scheduler/outbox health for alerting          |

`_shared/` holds code imported by more than one function (never
deployed as a function on its own — Supabase's CLI only treats a
top-level directory with an `index.ts` as a function).

## Local development

Install the [Supabase CLI](https://supabase.com/docs/guides/cli), then
from the repo root:

```sh
cp supabase/functions/.env.example supabase/functions/.env.local
# fill in supabase/functions/.env.local with real or test values

supabase start
supabase functions serve --env-file supabase/functions/.env.local
```

## Deploying

```sh
supabase functions deploy
supabase secrets set RESEND_API_KEY=... RESEND_FROM_ADDRESS=... \
  RESEND_WEBHOOK_SECRET=... CRON_SECRET=... APP_BASE_URL=...
```

Then run `../cron-setup.sql` once (see that file's own instructions)
to register the two cron jobs, and add this project's `resend-webhook`
URL as a webhook endpoint in the Resend dashboard.
