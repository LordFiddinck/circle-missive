# Phase 5 security, accessibility, and recovery review

Working checklist against `implementation_plan.md` Section 10's manual
release checklist and Section 7's security bullets, done as part of
Phase 5 ("Complete accessibility, responsive, security, performance, and
recovery testing"). Each item is marked:

- **Verified in code** — confirmed by reading the implementation; still
  worth spot-checking again after future changes.
- **Needs a live check** — requires a deployed project, a browser, or a
  human tester; couldn't be exercised from this environment (same
  constraint `e2e/README.md` already documents for Playwright — no
  network access here to run a Supabase instance or a browser).

Re-run the "needs a live check" rows yourself before actually inviting a
pilot group; this document doesn't replace that, it scopes it.

**Note from this pass:** `.github/workflows/check.yml` and
`deploy-pages.yml` — both described in detail in `README.md` and
assumed to exist by a comment in
`supabase/tests/database/000_stub_auth.sql` — were entirely absent from
the delivered project archive. Both are re-added as part of this
phase's hardening work (see the Security table below); since CI gating
is exactly what Phase 1's exit criteria and this phase's "automated
checks" depend on, treat verifying they actually pass on a real push as
a first live-check item, not an afterthought.

## Security

| Item                                                              | Status                                                                                          |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Invite tokens are hashed, random, expiring, single-use                | **Verified in code** — `0002_groups_memberships_invitations.sql` + its pgTAP tests                  |
| No raw HTML rendering of user content (`dangerouslySetInnerHTML`)     | **Verified in code** — none found anywhere in `src/`; answer/question text is always rendered as React text, never injected as HTML |
| Cross-group / cross-member data isolation via RLS                     | **Verified in code** — `0002_*.test.sql` and `0003_*.test.sql` include explicit cross-group and cross-member pgTAP assertions, not just same-group happy paths |
| Webhook signature verification, replay rejection                      | **Verified in code** — `resend-webhook/index.ts` verifies Svix HMAC signatures with a 5-minute timestamp tolerance |
| Privileged secrets never reach the frontend                           | **Verified in code** — only `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` are frontend env vars (`.env.example`); service-role, Resend, and cron secrets are Supabase project secrets consumed only in Edge Functions |
| Content-Security-Policy set                                           | **Verified in code** — `index.html`'s `default-src 'self'` meta tag; re-check it if a new external script/style source is ever added |
| Audit events exclude tokens/full answer bodies                        | **Verified in code** — `audit_events` payloads in the migrations carry ids/metadata, not answer text |
| CI runs format/lint/typecheck/tests/pgTAP/build on every change       | **Verified in code** — `.github/workflows/check.yml`; this and `deploy-pages.yml` were referenced throughout the README and `supabase/tests/database/000_stub_auth.sql` but were missing from the delivered archive (no `.github/` directory at all) — both were re-added this phase, unverified against a live GitHub Actions run (see that workflow's own header comment) |
| Automated dependency-update PRs configured                            | **Verified in code** — `.github/dependabot.yml` (npm + GitHub Actions ecosystems) |
| GitHub secret scanning / Dependabot alerts enabled                    | **Needs a live check** — a repository *setting* (Settings → Code security), not a file; `dependabot.yml` only covers version-update PRs, not this |
| Backups enabled and restore actually tested                           | **Needs a live check** — see `docs/operations-runbook.md`'s "Restoring a backup"                    |
| Penetration/abuse testing beyond the automated RLS suite               | **Needs a live check** — the pgTAP suite covers the authorization boundaries the plan calls out explicitly; broader testing (rate-limit abuse, enumeration) needs a running deployment |

## Accessibility

| Item                                                    | Status                                                                                       |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `eslint-plugin-jsx-a11y` enforced in CI                     | **Verified in code** — `eslint.config.js`, run by `check.yml` on every change                      |
| Status/error messages use `role="status"`/`role="alert"`    | **Verified in code** — consistent across every route/feature component                             |
| No color-only status indication                             | **Verified in code** — save/submit/delivery states are always paired with text, not color alone    |
| Skip link + focus moved to routed content on navigation     | **Verified in code** — added this phase; see `App.tsx`'s skip link and `#main-content` focus effect, needed because hash-routed navigation never triggers the browser's own focus reset |
| Keyboard-only walkthrough of the full cycle                 | **Needs a live check** — a human, ideally without a mouse, running through propose → finalize → answer → publish |
| Screen reader smoke test (VoiceOver/NVDA)                   | **Needs a live check** — same reasoning                                                            |
| Color contrast (AA) against final chosen palette            | **Needs a live check** — the current styling is close to unstyled system defaults; revisit once real visual design lands |

## Responsive / cross-browser

| Item                                        | Status               |
| ---------------------------------------------- | ------------------------ |
| Mobile Safari, mobile Chrome, desktop Chrome/Firefox/Safari | **Needs a live check** — Section 10's exact list; needs real devices/browsers |
| Answer editor offline/reconnect behavior      | **Verified in code** for the retry/local-recovery logic itself (`AnswerEditor.tsx` + its tests); the *felt* experience of an actual dropped connection still deserves a live check |

## Recovery

| Item                                             | Status                                                                                   |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Rerunning `scheduler-tick`/`email-worker` doesn't duplicate | **Verified in code** — idempotency keys, unique constraints, and dedupe are covered by the pgTAP suite (see `0004_scheduling_email.test.sql`) |
| Backup restore drill                                  | **Needs a live check** — see runbook                                                          |
| Incident response walkthrough                         | **Needs a live check** — tabletop the runbook's "Responding to a suspected data incident" with whoever's on call before the pilot, not just read it |

## Before the pilot

1. Work through every "Needs a live check" row above against an actual
   deployed project.
2. Publish `/privacy`, `/terms`, and `/help` (this phase adds the
   pages) with an operator's real contact details filled in — the
   shipped copy deliberately says "an operator should replace this" in
   a couple of places.
3. Get the privacy notice and terms reviewed by a lawyer if the pilot
   involves real personal answers (it will).
4. Confirm the "Alert ownership" names in the runbook are current people
   who will actually see the alerts.
