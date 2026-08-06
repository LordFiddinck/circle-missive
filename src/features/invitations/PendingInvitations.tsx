import { useState } from "react";
import { useNavigate } from "react-router-dom";
import type { PendingInvitation } from "./api";
import { useAcceptInvitationById } from "./queries";

function formatExpiry(value: string): string {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return "soon";
  return parsed.toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

type PendingInvitationsProps = {
  invitations: PendingInvitation[];
};

export function PendingInvitations({ invitations }: PendingInvitationsProps) {
  const navigate = useNavigate();
  const acceptInvitation = useAcceptInvitationById();
  const [acceptingId, setAcceptingId] = useState<string | null>(null);

  if (invitations.length === 0) return null;

  async function handleAccept(invitationId: string) {
    setAcceptingId(invitationId);
    try {
      const { groupId } = await acceptInvitation.mutateAsync(invitationId);
      navigate(`/groups/${groupId}`);
    } catch {
      // Error is surfaced inline below via acceptInvitation.isError;
      // acceptingId stays set so that item's message renders.
    }
  }

  return (
    <section aria-label="Pending invites">
      <h2>Pending invites</h2>
      <ul>
        {invitations.map((invitation) => {
          const isThisOnePending =
            acceptInvitation.isPending &&
            acceptingId === invitation.invitationId;
          const isThisOneErrored =
            acceptInvitation.isError && acceptingId === invitation.invitationId;

          return (
            <li key={invitation.invitationId}>
              <p>
                <strong>{invitation.groupName}</strong> &mdash; invited by{" "}
                {invitation.inviterDisplayName}. Expires{" "}
                {formatExpiry(invitation.expiresAt)}.
              </p>
              <button
                type="button"
                onClick={() => handleAccept(invitation.invitationId)}
                disabled={acceptInvitation.isPending}
              >
                {isThisOnePending ? "Accepting…" : "Accept"}
              </button>
              {isThisOneErrored ? (
                <p role="alert">
                  {acceptInvitation.error instanceof Error
                    ? acceptInvitation.error.message
                    : "Could not accept this invite."}
                </p>
              ) : null}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
