# End-to-end tests

Nothing lives here yet. This is a deliberate gap, not an oversight — worth
flagging explicitly:

Phase 3's exit criteria ("a test group completes a cycle manually;
refreshing/offline interruption does not lose the current draft;
publication never exposes another group or unsubmitted draft") are
covered today by two other layers instead:

- `supabase/tests/database/0003_cycles_questions_answers.test.sql` — pgTAP
  tests that run the full state machine (start → propose → finalize →
  autosave → submit → reopen → publish → late-answer → skip) against a
  real Postgres instance, including the cross-member and cross-group RLS
  isolation checks that are the actual security property Phase 3 cares
  about.
- `src/features/*/*.test.tsx` — component tests for the trickier client
  logic (the question-selection UI, the answer editor's live
  submit-readiness state).

A real Playwright run needs a live Supabase project (local via
`supabase start`, which requires Docker, or a hosted one) plus a way to
complete magic-link sign-in headlessly — locally that means driving
Supabase's local mail catcher UI, which wasn't available to set up and
verify in this environment. Rather than commit an unverified spec against
selectors/flows that couldn't actually be run here, this is left for
whoever next has a live stack to test against. `playwright.config.ts` is
in place so adding a spec file here is the only remaining step.
