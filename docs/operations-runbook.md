# Operations runbook

For the named operator/backup-operator pair called for in
`implementation_plan.md` Section 8 ("Establish ownership"). Written for
someone with `supabase` CLI access and dashboard access to the project,
during or after the Phase 5 pilot.

## Before you're on call

- Confirm you have: Supabase dashboard access, the `CRON_SECRET` project
  secret (or a way to fetch it), and the Resend dashboard login.
- Point an uptime monitor at the `health` function URL
  (`https://<project-ref>.functions.supabase.co/health`) and confirm it
  alerts on a non-200 response — see `supabase/functions/health/index.ts`
  for exactly what it checks (outbox backlog, oldest pending email,
  permanent failures, scheduler staleness).
- Know where backups live for your Supabase plan tier and how to trigger
  a restore in the dashboard before you need it for real.

## Replaying a scheduler tick

`scheduler-tick` runs on Supabase Cron every ~10 minutes
(`supabase/cron-setup.sql`), calling the idempotent `scheduler_tick()`
SQL function. To trigger it manually (e.g. after a deploy, or to confirm
it's healthy):

```sh
curl -X POST "https://<project-ref>.functions.supabase.co/scheduler-tick" \
  -H "Authorization: Bearer <CRON_SECRET>"
```

Safe to run repeatedly — `scheduler_tick()` only acts on cycles that are
actually due, and publication/next-cycle creation is idempotent (see
`0004_scheduling_email.sql`). A response body of
`{"cycles_examined": 0, "emails_enqueued": 0}` just means nothing was due
yet, not a failure.

## Retrying stuck mail

Check `health` first — `pending_outbox_count` and
`oldest_pending_seconds` tell you if anything is actually stuck versus
just recently queued. `email-worker` runs every ~2 minutes and claims a
batch via `claim_outbox_batch()`; retries already back off automatically.

To force an immediate pass instead of waiting for cron:

```sh
curl -X POST "https://<project-ref>.functions.supabase.co/email-worker" \
  -H "Authorization: Bearer <CRON_SECRET>"
```

If `permanently_failed_count` is nonzero, query
`email_outbox where status = 'failed'` in the SQL editor to see which
rows gave up and why, before deciding whether to requeue (reset
`status`/`attempts`) or write off (e.g. a permanently bounced address —
check `resend-webhook`'s suppression first, since that's often the real
cause).

## Extending or changing a cycle deadline

Organizers can do this themselves from the group's settings screen
(`change-cycle-deadline`, per the implementation plan's function table).
As an operator, you shouldn't normally need to do it directly in the
database — if you do (e.g. an organizer is unreachable and the group
needs an extension), do it through the same RPC the app uses rather than
hand-editing `cycles`, so the audit event and `next_action_at`
recalculation stay consistent.

## Restoring a backup

Follow your Supabase plan tier's point-in-time-recovery or backup
restore flow in the dashboard. Before the pilot, actually run a test
restore into a scratch project once — a documented process that's never
been exercised is not a tested one (see `implementation_plan.md`
Section 11: "backup restore and incident drill succeed" is a named exit
criterion for Phase 5, not just a nice-to-have).

## Rotating credentials

All of these are Supabase **project secrets**, never frontend/Pages
variables (see `README.md`'s deployment section):

| Secret                    | Used by                                 | Rotation notes                                                                                                                                                                                    |
| ------------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CRON_SECRET`             | `scheduler-tick`, `email-worker`        | Generate a new value (`openssl rand -hex 32`), `supabase secrets set`, then re-run `cron-setup.sql` with the new value before the old cron jobs next fire                                         |
| `RESEND_API_KEY`          | `email-worker`                          | Rotate in the Resend dashboard, then `supabase secrets set`                                                                                                                                       |
| `RESEND_WEBHOOK_SECRET`   | `resend-webhook`                        | Rotating invalidates in-flight webhook retries signed with the old secret — Resend will re-send; `resend-webhook` accepts either during a documented overlap window if you set both as candidates |
| Supabase service-role key | all Edge Functions (`supabaseAdmin.ts`) | Rotate from the Supabase dashboard; this immediately invalidates the old key everywhere it's used, so redeploy functions promptly after                                                           |

## Responding to a suspected data incident

1. Don't panic-rotate everything first — figure out scope (which table,
   which group, which time window) using `audit_events` and, if
   relevant, Supabase's own access logs.
2. Rotate the specific credential implicated (see above), not
   everything indiscriminately — over-rotation causes its own outages.
3. If group answer content was exposed beyond its intended audience,
   that's a matter for the privacy notice's incident-notification
   commitment — an operator should have one before a real pilot, not
   just this runbook.
4. Record what happened and the response as an `audit_events` row or an
   equivalent internal note; don't rely on memory afterward.

## Alert ownership

Name one person who receives `health`-monitor alerts and one backup who
knows this runbook. Review both names again before every pilot, since
"whoever set this up originally" tends to drift out of date silently.
