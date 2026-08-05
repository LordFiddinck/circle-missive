import { Link } from "react-router-dom";
import { useSession } from "@/lib/useSession";
import {
  useMyEmailPreferences,
  useUpdateMyEmailPreferences,
} from "@/features/notifications/queries";
import { LegalFooter } from "@/components/LegalFooter";

// The plan's Account/privacy screen (Section 2) also covers profile
// display name, group exit, and export/deletion requests — those stay
// out of scope here (see 0004_scheduling_email.sql's top comment);
// this page currently covers only what Phase 4 adds, email
// preferences, and can grow into the rest later without changing its
// route.
export default function Account() {
  const { session } = useSession();
  const userId = session?.user.id;
  const preferences = useMyEmailPreferences(userId);
  const updatePreferences = useUpdateMyEmailPreferences(userId ?? "");

  return (
    <main>
      <p>
        <Link to="/">&larr; Back to your groups</Link>
      </p>
      <h1>Account</h1>
      <p>
        Signed in as <strong>{session?.user.email}</strong>.
      </p>

      <h2>Email preferences</h2>
      <p>
        Invitations, phase updates, and deadline changes are always sent —
        they&rsquo;re how the site brings you back at the right moments. The
        two settings below are optional.
      </p>

      {preferences.isLoading ? (
        <p role="status">Loading your preferences…</p>
      ) : null}
      {preferences.isError ? (
        <p role="alert">Could not load your email preferences.</p>
      ) : null}

      {preferences.data ? (
        <fieldset disabled={updatePreferences.isPending}>
          <legend>Optional email</legend>

          <p>
            <label>
              <input
                type="checkbox"
                checked={preferences.data.reminders_enabled}
                onChange={(event) =>
                  updatePreferences.mutate({
                    reminders_enabled: event.target.checked,
                  })
                }
              />{" "}
              Deadline reminders (sent only if you haven&rsquo;t submitted yet)
            </label>
          </p>

          <p>
            <label>
              <input
                type="checkbox"
                checked={preferences.data.announcements_enabled}
                onChange={(event) =>
                  updatePreferences.mutate({
                    announcements_enabled: event.target.checked,
                  })
                }
              />{" "}
              Announcements (published issues, question suggestions ending
              soon)
            </label>
          </p>

          {preferences.data.suppressed ? (
            <p role="alert">
              Mail to your address has previously bounced or been marked as
              spam, so all optional email is currently paused. Contact a
              maintainer if this looks wrong.
            </p>
          ) : null}
        </fieldset>
      ) : null}

      {updatePreferences.isError ? (
        <p role="alert">Could not save that preference. Please try again.</p>
      ) : null}

      <LegalFooter />
    </main>
  );
}
