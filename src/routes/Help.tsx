import { Link } from "react-router-dom";
import { LegalFooter } from "@/components/LegalFooter";

export default function Help() {
  return (
    <main>
      <p className="back-link">
        <Link to="/sign-in">&larr; Back to sign in</Link>
      </p>

      <h1>Help</h1>

      <h2>How a cycle works</h2>
      <ol>
        <li>Your group&rsquo;s organizer opens a new cycle.</li>
        <li>
          Everyone can suggest questions for a little while. The organizer then
          opens answering, either by picking and ordering a final set or by
          releasing every suggestion in the order it was suggested. If
          suggestions are waiting when the question period ends, they&rsquo;re
          released for you automatically.
        </li>
        <li>
          Each member answers as many of the questions as they like. Drafts
          autosave as you type and are visible only to you until the issue is
          published.
        </li>
        <li>
          Near the deadline, anyone who hasn&rsquo;t submitted yet gets a
          reminder email.
        </li>
        <li>
          At the deadline (or whenever the organizer publishes early), anything
          you&rsquo;ve written but not yet submitted is submitted for you, and
          the answers become a shared issue your group can read. Questions you
          left blank are simply left out.
        </li>
        <li>
          The next cycle starts on its own, on your group&rsquo;s schedule.
        </li>
      </ol>

      <h2>Do I have to answer every question?</h2>
      <p>
        No. Answer the ones you like and leave the rest blank. You can press
        Submit with some questions empty; the blank ones just won&rsquo;t appear
        in the issue. If you only wrote answers and never pressed Submit,
        they&rsquo;re submitted for you when the cycle closes. If you
        didn&rsquo;t write anything, nothing is published under your name.
      </p>

      <h2>I submitted, but I want to change something</h2>
      <p>
        Submitting locks your answers. While the cycle is still open for
        answers, ask one of your group&rsquo;s organizers to reopen your
        submission from the cycle page, and you can edit and submit again. Once
        an issue is published, answers can&rsquo;t be edited, but you can still
        add an answer to any question you skipped. It&rsquo;s labeled
        &ldquo;added later.&rdquo;
      </p>

      <h2>Who sees my name on a question I suggest?</h2>
      <p>
        That&rsquo;s your choice. When you suggest a question, leave &ldquo;Show
        my name on this question&rdquo; ticked to be credited as the person who
        asked it, or untick it and other members will see
        &ldquo;Anonymous.&rdquo; You can change it on your own suggestion any
        time before the questions are released. After that, the question shows
        your name only if you chose to be credited.
      </p>

      <h2>I didn&rsquo;t get my sign-in email</h2>
      <p>
        Check your spam folder, and confirm you entered the exact address your
        invitation was sent to. Links expire after a while, so request a fresh
        one from the sign-in page if it&rsquo;s been sitting a while. If it
        still doesn&rsquo;t arrive, ask your group&rsquo;s organizer to resend
        your invitation.
      </p>

      <h2>My draft didn&rsquo;t save / I lost my connection</h2>
      <p>
        The answer editor keeps a local copy of what you&rsquo;ve typed, so a
        dropped connection or a refresh shouldn&rsquo;t lose your text — it
        retries saving automatically. If you see &ldquo;Could not save&rdquo;
        for more than a minute, check your connection and keep the tab open
        rather than closing it.
      </p>

      <h2>I can turn off some emails but not others — why?</h2>
      <p>
        Invitations, phase changes, and deadline notices are how the site brings
        you back at the right moment, so those stay on. Reminders and
        announcements are optional and can be turned off from your{" "}
        <Link to="/account">account page</Link>.
      </p>

      <h2>I want to leave a group, or have my data removed</h2>
      <p>
        To leave a group, open it and use <strong>Leave group</strong> at the
        bottom of the page. If you&rsquo;re the only organizer, make someone
        else an organizer first. For a data export or deletion request, reach
        this deployment&rsquo;s maintainer (self-serve export/deletion
        isn&rsquo;t built yet — see the{" "}
        <Link to="/privacy">privacy notice</Link>).
      </p>

      <LegalFooter />
    </main>
  );
}
