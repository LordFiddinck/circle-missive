import { Link } from "react-router-dom";
import { LegalFooter } from "@/components/LegalFooter";

export default function Privacy() {
  return (
    <main>
      <p>
        <Link to="/sign-in">&larr; Back to sign in</Link>
      </p>

      <h1>Privacy notice</h1>
      <p>
        <em>
          This describes what this Circle Missive deployment actually collects
          and does today. It is a starting point for an operator to adapt —
          including having it reviewed by a lawyer for their audience and
          jurisdiction — not a substitute for that review (see
          implementation_plan.md, Section 7).
        </em>
      </p>

      <h2>What we collect</h2>
      <ul>
        <li>
          <strong>Account:</strong> your email address and the display name you
          set.
        </li>
        <li>
          <strong>Group activity:</strong> which groups you belong to, your
          role, and invitations you send or receive.
        </li>
        <li>
          <strong>Your answers:</strong> the questions you propose and the
          answers you write, including autosaved drafts. Drafts are visible only
          to you; submitted answers become visible to your group only once a
          cycle is published.
        </li>
        <li>
          <strong>Email delivery records:</strong> which notifications were sent
          to you, their delivery status (delivered, bounced, complained), and
          your reminder/announcement preferences.
        </li>
        <li>
          <strong>Audit events:</strong> a record of role changes, deadline
          changes, membership changes, and publications, kept for
          accountability. These do not include your answer text.
        </li>
      </ul>

      <h2>Who can see it</h2>
      <p>
        Group organizers can see membership and completion status, but not your
        draft text. Other members can see your answers only after a cycle you
        submitted to is published. Database rules (Row Level Security) enforce
        this on every request, not just in the app&rsquo;s interface.
      </p>

      <h2>Who processes it</h2>
      <p>
        <a href="https://supabase.com/privacy" target="_blank" rel="noreferrer">
          Supabase
        </a>{" "}
        hosts our authentication, database, and server functions.{" "}
        <a
          href="https://resend.com/legal/privacy-policy"
          target="_blank"
          rel="noreferrer"
        >
          Resend
        </a>{" "}
        delivers our email. Neither is used for advertising, and we don&rsquo;t
        run advertising analytics on this site.
      </p>

      <h2>How long we keep it</h2>
      <p>
        Answers and issues are kept for as long as your group exists, so the
        archive stays complete. Expired/unused invitations, delivery records,
        and superseded drafts are not currently deleted automatically — an
        operator should set and document a retention schedule for these before a
        real pilot (see the operations runbook).
      </p>

      <h2>Your choices</h2>
      <ul>
        <li>
          Reminder and announcement email can be turned off from your{" "}
          <Link to="/account">account page</Link>. Invitations, phase changes,
          and deadline notices are sent regardless — they&rsquo;re how the site
          brings you back at the right moment.
        </li>
        <li>You can leave a group at any time by contacting its organizer.</li>
        <li>
          Self-serve data export and account deletion are planned but not built
          yet (see the project README&rsquo;s &ldquo;Not yet implemented&rdquo;
          section). Until then, contact this deployment&rsquo;s maintainer
          directly to request either.
        </li>
      </ul>

      <h2>Questions</h2>
      <p>
        This page is part of the Circle Missive template and doesn&rsquo;t name
        a specific contact — whoever operates a given deployment should replace
        this section with a real support contact before inviting a pilot group.
      </p>

      <LegalFooter />
    </main>
  );
}
