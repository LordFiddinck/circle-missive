import { useState } from "react";
import {
  useInvitations,
  useResendInvitation,
  useRevokeInvitation,
} from "./queries";

type InvitationListProps = {
  groupId: string;
};

function isEffectivelyExpired(status: string, expiresAt: string): boolean {
  return (
    status === "expired" ||
    (status === "pending" && new Date(expiresAt) < new Date())
  );
}

function buildInviteLink(token: string): string {
  return `${window.location.origin}${window.location.pathname}#/invite/${token}`;
}

export function InvitationList({ groupId }: InvitationListProps) {
  const invitations = useInvitations(groupId);
  const resendInvitation = useResendInvitation(groupId);
  const revokeInvitation = useRevokeInvitation(groupId);
  const [resentLink, setResentLink] = useState<{
    invitationId: string;
    link: string;
  } | null>(null);

  if (invitations.isLoading) {
    return <p role="status">Loading invitations…</p>;
  }

  if (invitations.isError) {
    return <p role="alert">Could not load invitations.</p>;
  }

  if (!invitations.data || invitations.data.length === 0) {
    return <p>No invitations sent yet.</p>;
  }

  async function handleResend(invitationId: string) {
    const result = await resendInvitation.mutateAsync(invitationId);
    setResentLink({ invitationId, link: buildInviteLink(result.token) });
  }

  return (
    <ul aria-label="Invitations">
      {invitations.data.map((invitation) => {
        const expired = isEffectivelyExpired(
          invitation.status,
          invitation.expires_at,
        );
        const displayStatus =
          expired && invitation.status === "pending"
            ? "expired"
            : invitation.status;
        return (
          <li key={invitation.id}>
            <span>
              {invitation.email_normalized} — {displayStatus}
            </span>
            {invitation.status === "pending" || expired ? (
              <>
                <button
                  type="button"
                  onClick={() => handleResend(invitation.id)}
                  disabled={resendInvitation.isPending}
                >
                  Resend
                </button>
                <button
                  type="button"
                  onClick={() => revokeInvitation.mutate(invitation.id)}
                  disabled={revokeInvitation.isPending || expired}
                >
                  Revoke
                </button>
              </>
            ) : null}
            {resentLink?.invitationId === invitation.id ? (
              <p role="status" aria-live="polite">
                New link: <code>{resentLink.link}</code>
              </p>
            ) : null}
          </li>
        );
      })}
      {(resendInvitation.isError || revokeInvitation.isError) && (
        <p role="alert">
          {resendInvitation.error instanceof Error
            ? resendInvitation.error.message
            : revokeInvitation.error instanceof Error
              ? revokeInvitation.error.message
              : "That change couldn't be made."}
        </p>
      )}
    </ul>
  );
}
