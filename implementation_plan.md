# Implementation Plan: A Private, Recurring Group Q&A Website

**Working name:** Circle Missive  
**Document status:** Proposed implementation plan  
**Recommended first release:** Responsive web application (works on phones and computers)  
**Recommended stack:** React + TypeScript on GitHub Pages; Supabase for authentication, PostgreSQL, and server functions; Resend for email

## 1. The bigger picture (for non-engineers)

### What we are building

This service helps a private group of friends, relatives, or colleagues keep in touch through recurring question-and-answer “issues.” Every group chooses its own rhythm—for example, every 2, 4, or 6 weeks.

In each cycle:

1. Members suggest questions.
2. The group organizer selects the final questions (automatic selection or voting can come later).
3. Every member receives an email and writes their answers on the website.
4. The service sends reminders to people who have not finished.
5. At the deadline, the completed answers are released as a shared issue that group members can read.
6. The next cycle is scheduled automatically.

The website is the private workspace and archive. Email brings people back at the right moments; members should not have to remember to check the site.

### The three pieces, in plain language

Think of the system as a small publication with three departments:

| Piece                             | Plain-language role                                    | Recommended service |
| --------------------------------- | ------------------------------------------------------ | ------------------- |
| Website (frontend/client)         | The pages people see and use                           | GitHub Pages        |
| Backend (database + server logic) | The locked filing cabinet and rule enforcer            | Supabase            |
| Email delivery                    | The postal service for invites, prompts, and reminders | Resend              |

GitHub Pages can publish the visual website, but it cannot safely hold private answers, run scheduled tasks, or keep email credentials secret. It is a **static hosting service** for HTML, CSS, and JavaScript. Therefore, GitHub Pages is suitable only for the frontend; Supabase supplies the missing backend. [GitHub Pages overview](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)

The browser communicates securely with Supabase over HTTPS. Supabase verifies who the member is and checks which group data they may access. Sensitive work, such as sending an email or advancing a cycle, runs in a protected server function where secret keys are not visible to visitors.

### What the first version should—and should not—do

The first version (MVP) should prove one complete recurring cycle:

- Create a group and choose its name, time zone, and interval.
- Invite members by email.
- Sign in through an emailed magic link.
- Propose questions; let the organizer finalize them.
- Draft, autosave, and submit answers.
- Email invitations and reminders.
- Publish an issue at the deadline and provide a private archive.
- Start the next cycle automatically.
- Let a member leave and request deletion of their account data.

Defer comments, reactions, photos, custom visual themes, question voting, mobile apps, PDF printing, AI-written summaries, and paid subscriptions. They are useful later, but each adds complexity before the core habit is proven.

### Recommended approach and why

Use a React/TypeScript single-page application built with Vite. Host the compiled static files on GitHub Pages. Use one Supabase project for login, a PostgreSQL database, access rules, scheduled jobs, and small server-side TypeScript functions. Use Resend through those server functions for application email.

This approach has few moving parts, can begin inexpensively, and does not require maintaining a traditional always-running server. It also leaves a migration path: if GitHub Pages becomes inconvenient, the same frontend can move to Cloudflare Pages, Netlify, or Vercel without redesigning the database.

### Important product decisions to confirm before coding

The plan assumes the following defaults:

- A cycle has a **question phase**, an **answer phase**, and a **published phase**.
- Members can see the final questions while answering, but not other members’ answers before publication.
- Draft answers are visible only to their author; submitted answers become visible to the group when the issue is published.
- The organizer can publish early, extend a deadline, reopen a submission, skip a cycle, and remove a member.
- Late answers may be added after publication and are labeled “added later.”
- The interval is measured from one cycle start to the next. The group stores a time zone so deadlines do not move unexpectedly with daylight-saving changes.
- One person can belong to multiple groups, with a separate role in each group.

Confirm these rules with 5–10 prospective users using simple screen sketches before implementing the database. Changing workflow rules later can require database and security changes.

## 2. User experience and functional requirements

### Roles

**Member**

- View only groups they belong to.
- Propose questions during the question phase.
- Draft, submit, and (until the deadline) revise their own answers.
- Read published issues in their groups.
- Control their display name and email preferences.

**Organizer**

- Has all member abilities.
- Edit group settings and cycle timing.
- Invite, resend an invite to, or remove members.
- Select and order final questions.
- Open, extend, skip, close, or publish a cycle.
- See completion status (but not private draft text).

Do not create a global staff/admin interface in the MVP. Operational database access should be limited to named maintainers and audited through the hosting dashboards.

### Primary screens

1. **Landing/sign-in:** brief explanation, email magic-link sign-in, privacy and terms links.
2. **Invitation acceptance:** group name, inviter, accept/decline, profile name.
3. **Group dashboard:** current phase, deadline, progress, main action, and recent issues.
4. **Question workshop:** propose, edit, and remove one’s suggestions; organizer selects/orders final set.
5. **Answer editor:** one question per section, autosave state, word count, validation, submit/reopen controls.
6. **Issue reader:** people-first or question-first reading layout, table of contents, late-answer label.
7. **Archive:** cycles ordered newest first with dates and completion summary.
8. **Members/settings:** roles, invite status, cadence, time zone, phase lengths, email preferences.
9. **Account/privacy:** profile, group exit, export request, account deletion request.

Design mobile-first. The answer editor must tolerate a temporary connection loss: retain unsaved text locally, retry, and clearly show `Saving…`, `Saved`, or `Could not save`.

### Accessibility and content design

- Target WCAG 2.2 AA: keyboard operation, visible focus, semantic labels, sufficient contrast, and screen-reader status messages.
- Never convey submission state by color alone.
- Use plain language and localize displayed dates to the group time zone.
- Ask for confirmation before destructive actions such as removing a member or discarding an answer.
- Provide text alternatives for any future uploaded images.

## 3. System architecture

```text
Member's browser
  |
  | HTTPS: sign-in, read permitted rows, save drafts
  v
GitHub Pages frontend (React/Vite) ------> Supabase Auth
  |                                           |
  | Supabase client with user access token    v
  +--------------------------------------> PostgreSQL
  |                                      (Row Level Security)
  |
  | HTTPS for privileged actions
  v
Supabase Edge Functions ----------------> Resend email API
  ^             |
  |             +-----------------------> PostgreSQL
  |
Supabase Cron (runs a scheduler periodically)
```

### Why there is no traditional always-on server

Most ordinary reads and writes can go from the signed-in browser to Supabase’s generated API. PostgreSQL Row Level Security (RLS) applies rules to every row, such as “the requester must be an active member of this row’s group.” Supabase documents browser-to-database access as safe when RLS is enabled and correctly configured. [Supabase RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security)

Privileged or multi-step operations go through Edge Functions: accepting an invitation, publishing an issue, changing cycle state, and sending email. Edge Functions are server-side TypeScript and keep provider credentials away from the browser. [Supabase Edge Functions](https://supabase.com/docs/guides/functions)

### Frontend implementation

- **Framework:** React, TypeScript, Vite.
- **Routing:** React Router with hash-based URLs (`/#/groups/...`) for the simplest GitHub Pages deployment. Alternatively configure a `404.html` fallback, but hash routing is less fragile for an MVP.
- **Data access:** `@supabase/supabase-js`; use a small query layer rather than calling it throughout UI components.
- **Forms:** schema validation (for example Zod) shared with Edge Functions where practical.
- **Styling:** a small accessible component system; avoid a large design framework until needed.
- **State:** server data via TanStack Query or a similarly focused cache; local editor state in React plus `localStorage` recovery.
- **Testing:** Vitest and Testing Library for units/components; Playwright for the critical cycle flow.
- **Configuration:** expose only the Supabase project URL and **publishable** key in the frontend. These are identifiers, not administrator secrets; RLS is the real protection.

Never place the Supabase secret/service-role key, Resend API key, Groq API key, SMTP password, or cron secret in source code, GitHub Pages output, browser storage, or a frontend environment variable. A frontend build-time “secret” becomes public once compiled.

### Server/client communication

Use JSON over HTTPS. There are two request patterns:

1. **Direct authenticated data request:** the frontend SDK sends the member’s short-lived access token to Supabase. RLS permits only allowed rows. Use this for reading group data, saving a member’s own draft, and updating their profile.
2. **Edge Function command:** the frontend calls a narrow endpoint such as `accept-invite`, `finalize-questions`, or `publish-cycle`. The function validates the access token, checks the caller’s role, validates input, performs the transaction, and returns a small JSON result.

Proposed functions:

| Function                         | Caller              | Responsibility                                                                                   |
| -------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------ |
| `accept-invite`                  | invited user        | Validate single-use invite and create membership                                                 |
| `invite-members`                 | organizer           | Create invitations and send invite emails                                                        |
| `finalize-questions`             | organizer           | Lock ordered questions and open answering                                                        |
| `submit-answers`                 | member              | Atomically mark all required answers submitted                                                   |
| `publish-cycle`                  | organizer/scheduler | Freeze release snapshot, publish, queue notifications                                            |
| `change-cycle-deadline`          | organizer           | Validate new timing and record audit event                                                       |
| `scheduler-tick`                 | cron only           | Advance due cycles and queue reminders safely                                                    |
| `generate-recommended-questions` | cron/scheduler only | Idempotently draft this cycle's `2n + 4` AI-suggested questions via the Groq API (see Section 4) |
| `email-worker`                   | cron/function       | Claim and send queued mail with retry controls                                                   |
| `request-data-export`            | member              | Create an export without exposing other members’ private data                                    |
| `request-account-deletion`       | member              | Start a documented deletion/anonymization workflow                                               |

All state-changing commands should be **idempotent**: retrying after a timeout must not publish twice or send duplicate mail. Give each command/event a unique key, use database transactions, and enforce unique constraints.

## 4. Database design

Use PostgreSQL migrations committed to Git. Do not rely on manual dashboard edits for production schema changes.

### Core tables

| Table                   | Important fields                                                                                                             | Purpose                                                                                                                                   |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `profiles`              | `user_id`, `display_name`, `locale`, timestamps                                                                              | Public-within-group user details; identity itself remains in Supabase Auth                                                                |
| `groups`                | `id`, `name`, `timezone`, `interval_days`, phase settings, `next_cycle_at`, `created_by`                                     | One recurring private circle and its schedule                                                                                             |
| `memberships`           | `group_id`, `user_id`, `role`, `status`, joined/left times                                                                   | Many-to-many membership and authorization source                                                                                          |
| `invitations`           | `id`, `group_id`, `email_normalized`, token hash, expiry, status, inviter                                                    | Single-use, expiring group invitations                                                                                                    |
| `cycles`                | `id`, `group_id`, sequence number, phase, starts/due/published times                                                         | One edition of the recurring workflow                                                                                                     |
| `question_proposals`    | `id`, `cycle_id`, `author_id`, text, timestamps                                                                              | Member suggestions before finalization                                                                                                    |
| `cycle_questions`       | `id`, `cycle_id`, proposal reference, final text, position                                                                   | Immutable ordered questions for answering                                                                                                 |
| `answers`               | `question_id`, `author_id`, body, draft/submitted times, revision                                                            | One member’s answer to one finalized question                                                                                             |
| `issue_entries`         | `cycle_id`, `question_id`, `author_id`, answer revision/body snapshot                                                        | Stable published content, unaffected by later draft edits                                                                                 |
| `email_preferences`     | `user_id`, per-category choices                                                                                              | Optional reminders and announcements; security mail remains mandatory                                                                     |
| `email_outbox`          | recipient, template, payload, status, attempts, `dedupe_key`, next attempt                                                   | Reliable, observable email delivery queue                                                                                                 |
| `audit_events`          | group/cycle, actor, event type, safe metadata, timestamp                                                                     | Accountability for role, deadline, membership, and publication changes                                                                    |
| `stock_questions`       | `id`, `category`, `text`, `description`, `locale`, `is_active`, timestamps                                                   | Curated, reusable question bank members can pull from when proposing questions                                                            |
| `recommended_questions` | `id`, `cycle_id`, `group_id`, `target_user_id` (nullable), `source_type`, `text`, `model`, `generation_run_id`, `created_at` | AI-drafted suggestions for the current cycle: personalized (visible only to `target_user_id`) or common-pool (visible to the whole group) |
| `recommendation_runs`   | `id`, `cycle_id` (unique), `status`, `member_count`, `requested_count`, `generated_count`, started/completed times, error    | One idempotent record per cycle guarding against duplicate AI generation                                                                  |

### Stock question bank

`stock_questions` is a small, editable content table, not a place for member-authored proposals — those still go through `question_proposals`. Seed it with a first batch per category and let a maintainer add more over time via migrations or a simple internal script; no admin UI is required for the MVP.

Categories are stored as a Postgres enum `question_category`:

```sql
create type question_category as enum (
  'check_in',
  'icebreakers',
  'random_fun',
  'worldview_life',
  'relationships',
  'work_career',
  'self_reflection'
);

create table stock_questions (
  id uuid primary key default gen_random_uuid(),
  category question_category not null,
  text text not null,
  description text,           -- optional one-line context/instructions shown under the question
  locale text not null default 'en',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index stock_questions_category_idx on stock_questions (category) where is_active;
```

In the question workshop screen, let members browse `stock_questions` by category (a simple tabbed or filterable list) and add one to their proposals with one click; this seeds the proposal with the stock text so the member can still edit it before submitting, and stores no reference back to the stock row (proposals remain independent, editable text). `stock_questions` is public read-only reference data — expose it with an RLS policy that allows read to any authenticated member (no group scoping needed, since it is shared across all groups) and restrict writes to the service role.

### AI-drafted recommended questions

Each cycle gets one batch of AI-drafted recommendations, generated once by a scheduled Edge Function rather than on demand, so results are stable and cheap. The plan uses the **Groq API** (OpenAI-compatible chat completions, free-tier friendly, fast inference) called only from the Edge Function — never from the browser.

**Composition of a batch**, for a group with `n` active members:

- **Personalized (2 per member → `2n` questions total):** for each member, the function looks at the questions _that member_ answered across the group's last three published issues and asks the model for 2 short new questions in a similar spirit/register. These rows have `target_user_id` set to that member and `source_type = 'personalized'`; RLS restricts them to that member only.
- **Common pool (4 per cycle):** the function also looks at the full set of finalized questions across _all_ members from the last three published issues (deduplicated) and asks the model for 4 new questions drawing on that broader pool. These rows have `target_user_id = null` and `source_type = 'common_pool'`; RLS allows any active member of the group to read them, so they can appear as shared inspiration in the question workshop alongside the stock bank.
- **Total: `2n + 4` questions per cycle**, matching the requested budget.

If a group has fewer than three published issues, use whatever history exists (an empty pool for a brand-new group means the prompt falls back to the stock bank, or the step is skipped for that member with `requested_count` reduced accordingly).

**Idempotency:** before calling Groq, the function inserts a row into `recommendation_runs` with `cycle_id` under a unique constraint. A second invocation for the same cycle (e.g., a retried scheduler tick) sees the existing row and exits without generating or storing anything twice.

```sql
create table recommendation_runs (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references cycles(id) unique,
  status text not null default 'pending', -- pending | running | completed | failed
  member_count int not null,
  requested_count int not null,   -- should equal 2*member_count + 4
  generated_count int,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  error text
);

create table recommended_questions (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references cycles(id),
  group_id uuid not null references groups(id),
  target_user_id uuid references profiles(user_id), -- null = common pool
  source_type text not null check (source_type in ('personalized','common_pool')),
  text text not null,
  model text not null,             -- e.g. 'llama-3.1-8b-instant' — record what actually generated it
  generation_run_id uuid not null references recommendation_runs(id),
  created_at timestamptz not null default now()
);

create index recommended_questions_cycle_idx on recommended_questions (cycle_id);
create index recommended_questions_target_idx on recommended_questions (cycle_id, target_user_id);
```

**Proposed function — `generate-recommended-questions`:**

| Function                         | Caller                             | Responsibility                                                                                                                                                                                                                                                                                                                                                  |
| -------------------------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `generate-recommended-questions` | scheduler (on question-phase open) | Idempotently claim a `recommendation_runs` row for the cycle, gather each member's per-user history and the group's common pool from the last three published issues, call Groq once per member plus once for the common pool (or batch into a single structured-output call), validate/length-limit the returned text, and insert `recommended_questions` rows |

Add this to the Edge Functions table in Section 3 alongside the existing functions. Store `GROQ_API_KEY` in Supabase secrets exactly like the Resend key — never in frontend code, build output, or browser storage. Because the free Groq tier has rate and token limits, keep prompts short (send only question _text_, not member identities or answer bodies) and add basic retry/backoff; treat a Groq failure as non-fatal to the cycle (log it, mark the run `failed`, and let the question workshop function normally using only the stock bank and member proposals).

RLS summary for the new tables:

- `stock_questions`: readable by any authenticated user; writable only by the service role.
- `recommended_questions` where `source_type = 'personalized'`: readable only where `target_user_id = auth.uid()` and the caller is an active member of `group_id`.
- `recommended_questions` where `source_type = 'common_pool'`: readable by any active member of `group_id`.
- `recommendation_runs`: not exposed to clients at all; service role only.

Use UUID primary keys, UTC timestamps (`timestamptz`), normalized lowercase email for matching, foreign keys, and uniqueness constraints. Store the group’s IANA time zone (for example `Europe/Zurich`) and calculate user-facing deadlines from it. Store `interval_days` or an equivalent validated duration; do not encode “monthly” as 30 days without deciding what users expect. If calendar-month recurrence is required, store a recurrence rule and explicitly handle dates such as the 31st.

Recommended indexes include memberships by `(user_id, status)`, cycles by `(group_id, sequence_no)`, answers by `(question_id, author_id)`, due cycles by `(phase, due_at)`, and unsent mail by `(status, next_attempt_at)`.

### Authorization/RLS rules

Enable RLS on **every** exposed table. Default to no access, then add explicit policies:

- Active members may read their group, active membership list, finalized questions, and published issue entries.
- Members may create/update only their own proposals and drafts in the correct phase.
- Members cannot read another person’s draft or submitted answer before publication.
- Organizers may manage group configuration and membership, but should see answer completion status rather than draft bodies.
- Only protected server functions may read invitation tokens, operate the outbox, snapshot publication, or write audit events.
- No anonymous database reads of groups, profiles, cycles, questions, or answers.

Put private operational tables in a non-exposed schema when possible. Test RLS using two users in different groups and an unauthenticated client. A passing happy-path test is insufficient; write tests that deliberately attempt cross-group reads and writes. Supabase warns that secret keys bypass RLS and must never be exposed to customers. [Supabase user administration](https://supabase.com/docs/guides/auth/users)

## 5. Scheduling and cycle state

Model the cycle as an explicit state machine:

```text
question_collection -> answering -> published
          |                |
          +---- skipped <--+
```

Only approved transitions are allowed. Record each transition in `audit_events`.

Run one `scheduler-tick` every 10–15 minutes (daily is also possible if exact timing is unimportant). It queries all records whose `next_action_at <= now()`, locks a small batch, and advances each safely. This supports different schedules without maintaining a cron job per group. Supabase Cron can invoke SQL or an Edge Function and records job runs. [Supabase Cron](https://supabase.com/docs/guides/cron)

For each cycle, persist actual timestamps rather than deriving them every time:

- `question_opens_at`
- `question_closes_at`
- `answer_opens_at`
- `answer_due_at`
- `published_at`
- `next_action_at`

When a group changes cadence, apply it to the next unpublished cycle by default and display the resulting dates before confirmation. Treat time-zone/DST calculations as a tested domain module, not scattered UI code.

## 6. Email communication

### Email types

- Group invitation and invitation reminder.
- Sign-in magic link/account verification (Supabase Auth).
- Question collection opened and ending soon.
- Answering opened, deadline reminder, and final reminder.
- Issue published.
- Deadline or schedule changed.
- Membership/security notification.

Every application email should contain the group name, a single clear action, the relevant deadline with time zone, why the recipient received it, and preference/help links. Do not put private answer text in email by default; link to the authenticated issue instead.

### Reliable delivery design

1. A transaction inserts an `email_outbox` row with a unique `dedupe_key`; it does not call the email provider while holding the main workflow open.
2. `email-worker` claims pending rows in small batches.
3. It sends through Resend using a server-side API key stored in Supabase secrets.
4. Success stores the provider message ID and sent time.
5. Temporary failure retries with increasing delays; permanent failure is marked and shown to an organizer/maintainer.
6. Provider webhooks update delivery/bounce/complaint status after signature verification.

Use a domain you control and configure SPF, DKIM, and preferably DMARC. Use a subdomain such as `mail.example.org`. Separate authentication emails from recurring application notifications if operational needs grow. Resend documents sending from Supabase Edge Functions and requires domain verification. [Resend + Supabase guide](https://resend.com/docs/knowledge-base/getting-started-with-resend-and-supabase)

Do not use GitHub Actions as the primary reminder scheduler. Repository workflows are deployment automation, not the business system of record; missed/delayed runs and secret handling would make cycle behavior harder to reason about.

## 7. Authentication, privacy, and security

### Authentication

Start with passwordless email magic links because the application is invitation-led and infrequently used. Add passkeys or passwords only if user research shows a need. Configure production redirect URLs for both the custom domain and GitHub Pages URL. Keep sessions reasonably long for convenience, but require a fresh sign-in for account deletion or changing the primary email.

### Security baseline

- HTTPS only; secure headers where the host allows them and a strict Content Security Policy via HTML meta/header configuration.
- RLS on all exposed tables, least-privilege grants, and automated negative authorization tests.
- Rate-limit invitations, magic-link requests, exports, and all Edge Functions.
- Hash invite tokens in the database; make them random, expiring, and single-use.
- Validate and length-limit all text on client and server. Render answer text as text/Markdown through a sanitizing renderer; never trust stored HTML.
- Keep all privileged secrets in Supabase/project secret storage and rotate them after suspected exposure.
- Verify webhook signatures and reject stale/replayed webhook events.
- Record security-relevant audit events without logging tokens, full answer bodies, or authentication headers.
- Enable database backups appropriate to the project tier and test restoration before launch.
- Keep dependencies updated; enable dependency and secret scanning in the source repository.

### Privacy and data lifecycle

Answers may contain intimate personal information. Before launch, write a short privacy notice stating what is collected, why, who can read it, processors used, retention, deletion/export rights, and a support contact. Obtain appropriate legal advice for the countries and audiences served, especially if children, health data, or workplace groups are involved.

Define these policies before coding deletion:

- Whether a departing member’s already-published answers remain, are anonymized, or are removed.
- How long expired invitations, logs, email events, unpublished drafts, and deleted accounts are retained.
- Whether organizers may export a whole issue and whether all members are told.
- Where Supabase and email-provider data is hosted and whether that meets the group’s jurisdiction needs.

Provide a member-level export. A user’s export must not silently include other people’s private data. Do not track advertising data. Keep product analytics minimal and privacy-preserving for the MVP.

## 8. Hosting and deployment

### GitHub Pages (frontend)

GitHub Pages hosts only the compiled `dist/` output. A GitHub Actions workflow should run formatting/type checks/tests, build the app, and deploy the artifact on merges to `main`. GitHub documents custom Pages deployments through Actions. [GitHub Pages custom workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)

Use a custom domain early enough to configure authentication redirects and email links once. If the source repository must remain private, confirm the selected GitHub plan supports the desired Pages setup. Even with a private repository, assume the deployed JavaScript and frontend configuration are public.

### Supabase (backend)

Maintain separate projects for development/staging and production if budget permits. Keep schema migrations, functions, and seed data in the repository under `supabase/`. Deploy database migrations first, then functions, then frontend. Protect production changes with review and a documented rollback.

### Environments and configuration

| Environment     | Frontend                     | Backend                                   | Email behavior              |
| --------------- | ---------------------------- | ----------------------------------------- | --------------------------- |
| Local           | Vite local server            | Local Supabase CLI or development project | Capture/test recipient only |
| Preview/staging | Optional Pages/preview host  | Staging Supabase project                  | Allowlisted recipients      |
| Production      | GitHub Pages + custom domain | Production Supabase project               | Verified production domain  |

Do not copy production personal data into development. Seed fictional groups and users instead.

### Monitoring and operations

- Alert on scheduler failure, accumulated outbox rows, repeated email failure, Edge Function error rate, and database capacity.
- Add a `/health` function that checks dependencies without returning secrets or personal data.
- Provide an internal runbook for replaying a scheduler tick, retrying mail, extending a deadline, restoring a backup, rotating credentials, and responding to a data incident.
- Establish ownership: one named person receives alerts, and one backup person knows the recovery process.

## 9. Implementation phases

### Phase 0 — Product definition and prototypes (about 1 week)

- Confirm workflow assumptions and privacy rules.
- Sketch the nine primary screens and test them with prospective users.
- Choose a name/domain and define success measures.
- Create a threat model: assets, actors, trust boundaries, likely misuse.

**Exit criteria:** five users can explain the cycle and complete a paper/clickable prototype without coaching; unresolved product decisions are recorded.

### Phase 1 — Project foundation (about 1 week)

- Create repository, React/Vite app, linting, formatting, tests, and Pages deployment.
- Create Supabase development project and migration workflow.
- Implement Auth, profiles, protected routing, shared errors, and accessibility baseline.
- Add CI checks and keep production secrets out of GitHub Pages builds.

**Exit criteria:** an invited test user can sign in on the deployed site; automated checks run on each change.

### Phase 2 — Groups, invites, and authorization (1–2 weeks)

- Implement groups, memberships, invitations, roles, and settings.
- Write RLS policies and cross-group attack tests.
- Build organizer invitation/member management screens.
- Integrate production-like auth email in staging.

**Exit criteria:** members can access only their own groups; expired/reused invites fail; organizer-only operations reject members.

### Phase 3 — Complete manual cycle (2 weeks)

- Implement state machine, proposals, final questions, draft autosave, submission, publication snapshot, and archive.
- Build organizer progress view without revealing drafts.
- Add idempotent Edge Function commands and audit events.

**Exit criteria:** a test group completes a cycle manually; refreshing/offline interruption does not lose the current draft; publication never exposes another group or unsubmitted draft.

### Phase 4 — Scheduling and email (1–2 weeks)

- Implement `next_action_at`, scheduler, outbox, worker, templates, retries, and deduplication.
- Connect Resend and verify domain records.
- Add preferences, unsubscribe behavior for optional mail, bounce/complaint handling, dashboards, and alerts.

**Exit criteria:** simulated 2-, 4-, and 6-week groups transition correctly; rerunning jobs creates neither duplicate issues nor duplicate emails; failures are visible and retryable.

### Phase 5 — Hardening and pilot (1–2 weeks)

- Complete accessibility, responsive, security, performance, and recovery testing.
- Publish privacy/terms/help content and operational runbook.
- Pilot with 2–3 real groups for at least one full cycle.
- Fix pilot issues and measure invitation acceptance, answer completion, and on-time publication.

**Exit criteria:** no critical/high security findings; backup restore and incident drill succeed; pilot users complete a cycle without developer intervention.

These are planning ranges, not promises. One experienced full-stack engineer can likely produce the MVP in roughly 7–10 focused weeks after product decisions are settled; unfamiliarity with Supabase, email deliverability, accessibility, or privacy work will increase that range.

## 10. Testing strategy

### Automated tests

- **Unit:** recurrence/date calculations, phase transitions, validation, permissions helpers, email dedupe keys.
- **Database:** constraints, migrations, RLS for anonymous/user/organizer/service roles, concurrent updates.
- **Component:** sign-in, proposal editor, answer autosave status, confirmations, keyboard/focus behavior.
- **End-to-end:** invite → join → propose → finalize → answer → remind → publish → read archive.
- **Failure cases:** expired tokens, email provider timeout, duplicated cron invocation, lost connection, stale browser session, two organizers acting simultaneously.

Use a controllable clock in tests so weeks do not need to pass. Test daylight-saving transitions and month boundaries in several time zones.

### Manual release checklist

- Mobile Safari, mobile Chrome, desktop Chrome/Firefox/Safari.
- Keyboard-only and screen-reader smoke test.
- No secret present in built assets or network responses.
- User A cannot access Group B by changing a URL or ID.
- Drafts are not in issue queries, emails, logs, or organizer views.
- Sign-in and email links return to the correct production domain.
- Scheduler/outbox dashboards are healthy; rollback is documented.

## 11. MVP acceptance criteria

The MVP is ready when all of the following are demonstrably true:

1. An organizer can create a private group with any supported interval and time zone.
2. An invited person can securely join, and an uninvited person cannot discover group content.
3. Members can propose questions and the organizer can finalize an ordered set.
4. Each member can safely autosave and submit answers; nobody else can read those drafts.
5. The service sends each required email once, retries temporary failures, and records delivery outcome.
6. A due cycle publishes one stable issue and schedules the next cycle exactly once.
7. Members can read only the published archive of groups they currently have permission to access.
8. Organizer changes and publication are audited.
9. Accessibility and authorization test suites pass in CI.
10. A named operator can diagnose a failed scheduled job and restore data using the runbook.

## 12. Risks and mitigations

| Risk                                                | Mitigation                                                                                                  |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| GitHub Pages is mistaken for a complete server      | Document that it hosts only public frontend assets; use Supabase for all private/stateful work              |
| A bad RLS rule leaks another group’s answers        | Default-deny policies, non-exposed schemas, cross-tenant tests, security review before pilot                |
| Reminder emails land in spam                        | Verified domain, SPF/DKIM/DMARC, clear content, low complaint rate, bounce monitoring                       |
| Cron/function retries duplicate mail or publication | Transactions, row locks, stable dedupe keys, unique constraints, idempotent handlers                        |
| Users lose long answers                             | Debounced server autosave, local recovery copy, visible save status, navigation warning                     |
| Ambiguous “monthly” timing surprises users          | Show exact next dates, store time zone, test DST, define calendar-month vs fixed-day behavior               |
| Vendor limits/prices change                         | Check current limits before pilot, monitor usage, keep standard PostgreSQL migrations and portable frontend |
| Personal writing creates privacy/legal exposure     | Data minimization, clear audience rules, retention/deletion policy, appropriate legal review                |

## 13. Suggested repository structure

```text
circle-missive/
├── .github/workflows/
│   ├── check.yml
│   └── deploy-pages.yml
├── docs/
│   ├── architecture-decisions/
│   ├── privacy-data-map.md
│   └── operations-runbook.md
├── src/
│   ├── components/
│   ├── features/
│   │   ├── auth/
│   │   ├── groups/
│   │   ├── questions/
│   │   ├── answers/
│   │   └── issues/
│   ├── lib/
│   └── routes/
├── supabase/
│   ├── functions/
│   ├── migrations/
│   ├── seed.sql
│   └── tests/
├── e2e/
├── public/
└── package.json
```

## 14. Immediate next actions

1. Decide the six product assumptions listed in Section 1, especially when answers become visible and what happens to published answers after a member leaves.
2. Interview 5–10 potential users and test a lightweight screen prototype.
3. Choose a domain and verify that the intended GitHub plan/repository visibility suits the project.
4. Create a Supabase development project and a Resend test account, but do not enter production data.
5. Build a one-group “walking skeleton”: sign in, read one permitted group row through RLS, call one authenticated Edge Function, and deploy the frontend to GitHub Pages.
6. Review the skeleton’s authorization before expanding to the full schema.

## 15. Reference documentation

- [What is GitHub Pages?](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)
- [GitHub Pages custom deployment workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [Supabase database overview](https://supabase.com/docs/guides/database/overview)
- [Supabase Auth](https://supabase.com/docs/guides/auth)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Supabase scheduled Edge Functions](https://supabase.com/docs/guides/functions/schedule-functions)
- [Resend with Supabase](https://resend.com/docs/knowledge-base/getting-started-with-resend-and-supabase)
- [Groq API documentation](https://console.groq.com/docs/overview)

---

**Architecture decision summary:** GitHub Pages is recommended for the public frontend assets, not as the application server. Supabase is the system of record and authorization boundary. Resend sends email only from protected Supabase functions. This is the smallest credible architecture for a private, scheduled, email-driven group Q&A service.
