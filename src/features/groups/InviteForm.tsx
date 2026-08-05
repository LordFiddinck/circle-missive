import { useState, type FormEvent } from "react";
import { useCreateInvitation } from "./queries";

type InviteFormProps = {
  groupId: string;
};

function buildInviteLink(token: string): string {
  return `${window.location.origin}${window.location.pathname}#/invite/${token}`;
}

export function InviteForm({ groupId }: InviteFormProps) {
  const createInvitation = useCreateInvitation(groupId);
  const [email, setEmail] = useState("");
  const [lastLink, setLastLink] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setCopied(false);
    const result = await createInvitation.mutateAsync(email.trim());
    setLastLink(buildInviteLink(result.token));
    setEmail("");
  }

  async function handleCopy() {
    if (!lastLink) return;
    await navigator.clipboard.writeText(lastLink);
    setCopied(true);
  }

  return (
    <div>
      <form onSubmit={handleSubmit}>
        <label htmlFor="invite-email">Invite by email</label>
        <input
          id="invite-email"
          name="invite-email"
          type="email"
          required
          value={email}
          onChange={(event) => setEmail(event.target.value)}
        />
        <button
          type="submit"
          disabled={createInvitation.isPending || email.trim() === ""}
        >
          {createInvitation.isPending
            ? "Creating invite…"
            : "Create invite link"}
        </button>
      </form>

      {createInvitation.isError ? (
        <p role="alert">
          {createInvitation.error instanceof Error
            ? createInvitation.error.message
            : "Could not create the invite."}
        </p>
      ) : null}

      {lastLink ? (
        <p role="status" aria-live="polite">
          Invite sent — an email is on its way. You can also share the link
          directly:
          <br />
          <code>{lastLink}</code>{" "}
          <button type="button" onClick={handleCopy}>
            {copied ? "Copied!" : "Copy link"}
          </button>
        </p>
      ) : null}
    </div>
  );
}
