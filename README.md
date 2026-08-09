# Circle Missive

A private, recurring group Q&A site. See `implementation_plan.md` (repo
root, alongside this README once you copy it in) for the full product and
architecture plan this codebase follows.

**Status:** Phase 5 — hardening and pilot prep. Sign-in, groups,
invitations, and membership management work end to end (Phase 2), and
groups run a full cycle by hand or automatically: propose and finalize
questions, answer with autosave, submit, publish, and browse the archive
(Phase 3). Cycles that reach their deadline publish and roll over to the
next cycle on their own, and the site sends real email — invites,
phase-open notices, deadline reminders, and published-issue
announcements — with preferences, one-click unsubscribe, retries, and
bounce/complaint handling (Phase 4). As of Phase 5, the app has public
privacy/terms/help pages, a hash-routing accessibility fix (skip link +
focus management), `docs/` has an operations runbook, a privacy data
map, and a pre-pilot security/accessibility/recovery checklist, and the
`.github/workflows/` CI/deploy setup and `dependabot.yml` — described in
this README all along but missing from the project archive this phase
started from — have been (re)added. See "What's implemented so far"
below, `docs/security-review.md` for what still needs a live deployment
to verify, and `implementation_plan.md` Section 9 for what's still
ahead.

## Stack

- React + TypeScript + Vite, deployed to GitHub Pages
- Supabase: Auth (magic link), PostgreSQL with Row Level Security, Edge
  Functions, Cron
- Resend for application email, via `email-worker`/`scheduler-tick`/
  `resend-webhook` — see `supabase/functions/README.md`
- Groq API for AI-drafted recommended questions — not yet implemented;
  see "Not yet implemented" below

## Local setup

1. Install dependencies:

   ```bash
   npm install
   ```

2. Create a Supabase project (or run one locally with the Supabase CLI —
   `supabase start`, requires Docker).

3. Copy `.env.example` to `.env.local` and fill in your project's URL and
   publishable ("anon") key:

   ```bash
   cp .env.example .env.local
   ```

4. Apply migrations:

   ```bash
   supabase db push
   # or, for a local Supabase instance:
   supabase db reset
   ```

5. Start the dev server:

   ```bash
   npm run dev
   ```

6. Visit `http://localhost:5173`, enter an email address, and check that
   inbox (or Supabase Studio's local mail inbox at
   `http://localhost:54324` if running Supabase locally) for the sign-in
   link.

7. (Optional, for scheduling/email) Serve the Edge Functions locally and
   register the cron jobs — see `supabase/functions/README.md` and
   `supabase/cron-setup.sql`. The rest of the app works without this;
   it's only needed to exercise automatic cycle advancement and outgoing
   mail locally.

## Scripts

| Command                           | Purpose                                                                    |
| --------------------------------- | -------------------------------------------------------------------------- |
| `npm run dev`                     | Local dev server                                                           |
| `npm run build`                   | Type-checked production build                                              |
| `npm run lint`                    | ESLint                                                                     |
| `npm run format` / `format:check` | Prettier                                                                   |
| `npm run typecheck`               | `tsc --noEmit`                                                             |
| `npm test`                        | Vitest unit/component tests                                                |
| `npm run e2e`                     | Playwright end-to-end tests — scaffolding only so far, see `e2e/README.md` |

## Deployment

`deploy-pages.yml` builds and publishes `dist/` to GitHub Pages on every
push to `main`, after `check.yml` passes. Set these **repository
secrets** (Settings → Secrets and variables → Actions):

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

And, only if deploying under `https://<user>.github.io/<repo>/` rather
than a custom domain, this **repository variable**:

- `VITE_BASE_PATH` = `/circle-missive/`

Never add the Supabase **service-role** key, Resend key, or Groq key as a
frontend/Pages secret — those belong only in Supabase project secrets,
consumed by Edge Functions server-side.

### Deploying the scheduling/email backend

`deploy-pages.yml` only builds and publishes the frontend. The Edge
Functions and cron jobs are deployed separately (not yet wired into CI):

1. `supabase functions deploy`
2. Set the project secrets listed in `supabase/functions/.env.example`
   via `supabase secrets set`.
3. Run `supabase/cron-setup.sql` once (via the SQL Editor or
   `supabase db execute`) to register the `scheduler-tick` and
   `email-worker` cron jobs — see that file for the exact prerequisites.
4. Add this project's `resend-webhook` function URL as a webhook
   endpoint in the Resend dashboard, and verify a sending domain there
   before `RESEND_FROM_ADDRESS` will work.
5. Point an uptime monitor at the `health` function URL and alert on a
   non-200 response.

## What's implemented so far (Phases 1–4)

- Vite + React + TypeScript app, hash-based routing
- ESLint (with `jsx-a11y`), Prettier, Vitest + Testing Library, Playwright
  scaffolding — `supabase/functions/**` (Deno, a separate runtime) is
  excluded from both and uses its own tooling; see that directory's README
- `check.yml` CI: format check, lint, typecheck, unit tests, pgTAP
  database tests, build
- `deploy-pages.yml`: build + deploy to GitHub Pages on `main`, gated on
  `check.yml` passing (`workflow_run`)
- `dependabot.yml`: weekly grouped dependency-update PRs for npm and
  GitHub Actions
- Supabase `profiles` table synced from `auth.users`, RLS restricting
  each user to their own row
- Magic-link sign-in (`/sign-in`) and a protected `/` dashboard route
  that redirects signed-out visitors
- Groups, memberships, and email invitations (create/accept/resend/revoke),
  with an audited `remove_member` / `leave_group` / `set_member_role`
- The full cycle, manual or automatic: an organizer opens a cycle (or the
  scheduler does, once the previous one publishes), members suggest
  questions, the organizer finalizes an ordered set, members answer with
  autosaving drafts (recoverable after a refresh or dropped connection)
  and submit, the cycle publishes a snapshot — by the organizer or
  automatically at the deadline — and late answers can be added
  afterward. Organizers get a completion view that never exposes draft
  text, and a group's full cycle history is browsable in its archive.
- Scheduling: `next_action_at` + `scheduler_tick()` auto-publish a cycle
  and start the next one at the deadline, send deadline reminders to
  members who haven't submitted, and nudge organizers about an overdue,
  unfinalized question phase (automatic question _selection_ is
  deliberately out of scope — see `0004_scheduling_email.sql`'s header
  comment)
- Email: a durable outbox with dedupe, capped-backoff retries, and
  permanent-failure marking; Resend integration via `email-worker`;
  per-user reminders/announcements preferences with one-click
  unsubscribe (`/unsubscribe/:token/:category`, works signed out);
  bounce/complaint handling that suppresses further mail via
  `resend-webhook`; an organizer-facing email-activity view on each
  group page; and a `health` endpoint for uptime monitoring/alerting
- Public `/privacy`, `/terms`, and `/help` pages (reachable signed out,
  linked from sign-in and the account page), a skip link, and
  focus-moves-to-content-on-navigation (hash routing doesn't trigger the
  browser's own focus reset, so this needed doing explicitly) —
  `docs/security-review.md` has the fuller accessibility/security/
  recovery checklist this phase worked through, and what in it still
  needs a live deployment or a human tester to finish
- `docs/operations-runbook.md` (replaying the scheduler, retrying mail,
  rotating credentials, restoring a backup, a data-incident checklist)
  and `docs/privacy-data-map.md` (what's stored where, retention, open
  policy questions an operator needs to decide before a real pilot)

## Not yet implemented

The stock question bank and AI-drafted recommended questions (Groq)
remain out of scope — Phase 4's own plan section doesn't call for them,
so they stay future work alongside account/privacy features like
profile editing, group export, and data-deletion requests. See
`implementation_plan.md` Section 9 for the phase-by-phase order these
arrive in.
