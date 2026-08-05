import { Link } from "react-router-dom";
import { LegalFooter } from "@/components/LegalFooter";

export default function Help() {
  return (
    <main>
      <p>
        <Link to="/sign-in">&larr; Back to sign in</Link>
      </p>

      <h1>Help</h1>

      <h2>How a cycle works</h2>
      <ol>
        <li>Your group&rsquo;s organizer opens a new cycle.</li>
        <li>
          Everyone can suggest questions for a little while; the organizer
          picks and orders the final set.
        </li>
        <li>
          Each member writes their answers. Drafts autosave as you type and
          are only visible to you until you submit.
        </li>
        <li>
          Near the deadline, anyone who hasn&rsquo;t submitted yet gets a
          reminder email.
        </li>
        <li>
          At the deadline (or whenever the organizer publishes early), the
          submitted answers become a shared issue everyone in the group can
          read. Missed a deadline? You can still add a late answer
          afterward — it&rsquo;s labeled &ldquo;added later.&rdquo;
        </li>
        <li>The next cycle starts on its own, on your group&rsquo;s schedule.</li>
      </ol>

      <h2>I didn&rsquo;t get my sign-in email</h2>
      <p>
        Check your spam folder, and confirm you entered the exact address
        your invitation was sent to. Links expire after a while, so request
        a fresh one from the sign-in page if it&rsquo;s been sitting a
        while. If it still doesn&rsquo;t arrive, ask your group&rsquo;s
        organizer to resend your invitation.
      </p>

      <h2>My draft didn&rsquo;t save / I lost my connection</h2>
      <p>
        The answer editor keeps a local copy of what you&rsquo;ve typed, so
        a dropped connection or a refresh shouldn&rsquo;t lose your text —
        it retries saving automatically. If you see &ldquo;Could not
        save&rdquo; for more than a minute, check your connection and keep
        the tab open rather than closing it.
      </p>

      <h2>I can turn off some emails but not others — why?</h2>
      <p>
        Invitations, phase changes, and deadline notices are how the site
        brings you back at the right moment, so those stay on. Reminders
        and announcements are optional and can be turned off from your{" "}
        <Link to="/account">account page</Link>.
      </p>

      <h2>I want to leave a group, or have my data removed</h2>
      <p>
        Contact your group&rsquo;s organizer to leave, or reach this
        deployment&rsquo;s maintainer for a data export or deletion request
        (self-serve export/deletion isn&rsquo;t built yet — see the{" "}
        <Link to="/privacy">privacy notice</Link>).
      </p>

      <LegalFooter />
    </main>
  );
}
