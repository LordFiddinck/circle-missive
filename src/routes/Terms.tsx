import { Link } from "react-router-dom";
import { LegalFooter } from "@/components/LegalFooter";

export default function Terms() {
  return (
    <main>
      <p>
        <Link to="/sign-in">&larr; Back to sign in</Link>
      </p>

      <h1>Terms of use</h1>
      <p>
        <em>
          A starting point for an operator to adapt for their own pilot, not
          finished legal terms — see implementation_plan.md, Section 7, on
          getting appropriate legal review before a real launch.
        </em>
      </p>

      <h2>What this service is</h2>
      <p>
        Circle Missive is a private tool for a group you already know
        (friends, relatives, or colleagues) to answer recurring questions
        together by email and a shared archive. It is not a public forum:
        content is visible only within the group that produced it.
      </p>

      <h2>Your account and content</h2>
      <ul>
        <li>
          You&rsquo;re responsible for what you write, and for keeping your
          sign-in email address secure. Sign-in uses a one-time emailed
          link rather than a password.
        </li>
        <li>
          You keep ownership of what you write. By submitting an answer,
          you agree it can be shown to the other members of that group once
          the cycle is published, and kept in that group&rsquo;s archive.
        </li>
        <li>
          Group organizers can remove a member, extend or reopen a
          deadline, and publish early — these actions are recorded in the
          group&rsquo;s audit log.
        </li>
      </ul>

      <h2>Acceptable use</h2>
      <p>
        Don&rsquo;t use this service to harass another member, to share
        content you don&rsquo;t have the right to share, or to try to access
        a group you haven&rsquo;t been invited to. An operator may remove a
        member or suspend a group that violates this.
      </p>

      <h2>Availability</h2>
      <p>
        This is a small, self-hosted-style tool without a service-level
        guarantee. An operator should describe their own uptime and support
        expectations here before a pilot, and keep backups current (see the
        operations runbook).
      </p>

      <h2>Changes</h2>
      <p>
        An operator may need to update these terms as the product changes.
        Material changes should be communicated to members in advance,
        not just posted silently on this page.
      </p>

      <LegalFooter />
    </main>
  );
}
