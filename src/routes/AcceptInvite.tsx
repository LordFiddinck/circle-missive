import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { supabase } from "@/lib/supabaseClient";
import { useSession } from "@/lib/useSession";
import {
  useAcceptInvitation,
  useInvitationPreview,
} from "@/features/groups/queries";

function isEffectivelyExpired(status: string, expiresAt: string): boolean {
  return (
    status === "expired" ||
    (status === "pending" && new Date(expiresAt) < new Date())
  );
}

export default function AcceptInvite() {
  const { token } = useParams<{ token: string }>();
  const navigate = useNavigate();
  const { session, loading: sessionLoading } = useSession();
  const preview = useInvitationPreview(token);
  const acceptInvitation = useAcceptInvitation();
  const [magicLinkSent, setMagicLinkSent] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);

  async function sendMagicLink(email: string) {
    setSendError(null);
    const redirectTo = `${window.location.origin}${window.location.pathname}?invite=${token}`;
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: redirectTo },
    });
    if (error) {
      setSendError(error.message);
      return;
    }
    setMagicLinkSent(true);
  }

  async function handleAccept() {
    if (!token) return;
    const result = await acceptInvitation.mutateAsync(token);
    navigate(`/groups/${result.groupId}`, { replace: true });
  }

  if (!token) {
    return (
      <main>
        <p role="alert">This invite link is missing its token.</p>
      </main>
    );
  }

  if (preview.isLoading || sessionLoading) {
    return (
      <main>
        <p role="status" aria-live="polite">
          Checking your invite…
        </p>
      </main>
    );
  }

  if (preview.isError || !preview.data) {
    return (
      <main>
        <h1>Invite not found</h1>
        <p>
          This invite link isn&rsquo;t valid. Ask whoever invited you to send a
          new one.
        </p>
      </main>
    );
  }

  const invite = preview.data;

  if (invite.status === "revoked") {
    return (
      <main>
        <h1>Invite revoked</h1>
        <p>
          This invite to {invite.groupName} has been revoked by its organizer.
        </p>
      </main>
    );
  }

  if (invite.status === "accepted") {
    return (
      <main>
        <h1>Already used</h1>
        <p>This invite to {invite.groupName} has already been accepted.</p>
      </main>
    );
  }

  if (isEffectivelyExpired(invite.status, invite.expiresAt)) {
    return (
      <main>
        <h1>Invite expired</h1>
        <p>
          This invite to {invite.groupName} has expired. Ask its organizer to
          send a new one.
        </p>
      </main>
    );
  }

  const signedInEmail = session?.user.email?.toLowerCase();
  const emailMatches = signedInEmail === invite.emailNormalized;

  return (
    <main>
      <h1>You&rsquo;re invited to {invite.groupName}</h1>
      <p>
        {invite.inviterDisplayName} invited{" "}
        <strong>{invite.emailNormalized}</strong> to join.
      </p>

      {!session ? (
        magicLinkSent ? (
          <p role="status" aria-live="polite">
            Check your inbox for a sign-in link, then come back to this page to
            accept.
          </p>
        ) : (
          <>
            <p>Sign in with that email address to accept.</p>
            <button
              type="button"
              onClick={() => sendMagicLink(invite.emailNormalized)}
            >
              Send sign-in link to {invite.emailNormalized}
            </button>
            {sendError ? (
              <p role="alert">Could not send the link: {sendError}</p>
            ) : null}
          </>
        )
      ) : emailMatches ? (
        <>
          <button
            type="button"
            onClick={handleAccept}
            disabled={acceptInvitation.isPending}
          >
            {acceptInvitation.isPending
              ? "Joining…"
              : `Accept and join ${invite.groupName}`}
          </button>
          {acceptInvitation.isError ? (
            <p role="alert">
              Could not accept the invite:{" "}
              {acceptInvitation.error instanceof Error
                ? acceptInvitation.error.message
                : "Unknown error"}
            </p>
          ) : null}
        </>
      ) : (
        <>
          <p role="alert">
            You&rsquo;re signed in as {session.user.email}, but this invite was
            sent to {invite.emailNormalized}. Sign out and sign in with that
            address to accept.
          </p>
          <button type="button" onClick={() => supabase.auth.signOut()}>
            Sign out
          </button>
        </>
      )}
    </main>
  );
}
