# Privacy data map

Internal companion to `src/routes/Privacy.tsx` (the public-facing
notice). Written from the actual schema (`supabase/migrations/`), for
whoever needs to answer "what do we actually store and where" precisely
— during a security review, a pilot's legal review, or an access/export
request. Keep this in sync with migrations as they change.

| Data                                                        | Table(s)                                    | Who can read it (via RLS)                                                           | Retention today                                                         |
| ----------------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Email address, display name                                 | `auth.users` (Supabase-managed), `profiles` | The user themselves; group co-members see display name only                         | Until account deletion (not yet self-serve — see README)                |
| Group membership, role                                      | `memberships`                               | Group members and the organizer                                                     | Until membership is removed/left                                        |
| Invitations (email, hashed token, status)                   | `invitations`                               | The group's organizer                                                               | Not currently purged after expiry — see "Open questions" below          |
| Question proposals                                          | `question_proposals`                        | Group members during the question phase                                             | Kept indefinitely as part of cycle history                              |
| Finalized questions                                         | `cycle_questions`                           | Group members                                                                       | Kept indefinitely (immutable once finalized)                            |
| Draft and submitted answers                                 | `answers`                                   | The author only, until publication                                                  | Kept indefinitely; drafts superseded by a submission are not purged     |
| Published issue content                                     | `issue_entries`                             | Group members, once published                                                       | Kept indefinitely — this is the product's archive                       |
| Email preferences, unsubscribe tokens                       | `email_preferences`                         | The user themselves                                                                 | Until account deletion                                                  |
| Email delivery records                                      | `email_outbox`                              | Organizers see aggregate activity, not full payloads (`get_group_email_activity()`) | Not currently purged — see "Open questions"                             |
| Audit events (role/deadline/membership/publication changes) | `audit_events`                              | Organizers, for their own group's events                                            | Kept indefinitely for accountability; contains no answer text or tokens |

## Processors

- **Supabase** — hosts Postgres (all tables above), Auth, and Edge
  Functions. See their [privacy policy](https://supabase.com/privacy)
  and choose a project region appropriate to your users before a real
  pilot.
- **Resend** — sends all application email (invites, reminders,
  announcements, published-issue notices) from Edge Functions only; the
  API key never reaches the browser. See their
  [privacy policy](https://resend.com/legal/privacy-policy).

No advertising or analytics processor is used.

## Open questions for an operator before a real pilot

These are genuinely undecided in the current implementation, not
oversights to silently work around — the implementation plan (Section 7)
calls them out as decisions to make explicitly:

1. **Retention schedule.** Expired invitations, superseded drafts, and
   old `email_outbox` rows currently accumulate with no automatic purge.
   Decide a schedule and, if adopted, implement it as a scheduled SQL
   job alongside `scheduler_tick()`.
2. **Departing-member answers.** When a member leaves, does their
   already-published `issue_entries` content stay, get anonymized, or
   get removed? This affects the rest of the group's archive, so it
   needs a decision, not just a default.
3. **Export/deletion self-service.** Not built yet (README's "Not yet
   implemented"). Until it exists, requests are handled manually by an
   operator directly in the database — log that you did it as an
   `audit_events`-equivalent note, and make sure a user's export never
   includes another member's private draft or unpublished answer.
4. **Data residency.** Confirm your Supabase project region and Resend
   sending region meet your pilot group's jurisdiction needs.
