import { Link } from "react-router-dom";
import { supabase } from "@/lib/supabaseClient";
import { useSession } from "@/lib/useSession";
import { useGroups } from "@/features/groups/queries";
import { useMyPendingInvitations } from "@/features/invitations/queries";
import { PendingInvitations } from "@/features/invitations/PendingInvitations";

export default function Dashboard() {
  const { session } = useSession();
  const groups = useGroups();
  const pendingInvitations = useMyPendingInvitations(session?.user.id);

  return (
    <main>
      <h1>Your groups</h1>
      <p>
        Signed in as <strong>{session?.user.email}</strong>.
      </p>

      {pendingInvitations.isLoading ? (
        <p role="status">Checking for pending invites…</p>
      ) : null}
      {pendingInvitations.isError ? (
        <p role="alert">Could not load your pending invites.</p>
      ) : null}
      {pendingInvitations.data ? (
        <PendingInvitations invitations={pendingInvitations.data} />
      ) : null}

      {groups.isLoading ? <p role="status">Loading your groups…</p> : null}
      {groups.isError ? <p role="alert">Could not load your groups.</p> : null}

      {groups.data && groups.data.length > 0 ? (
        <ul aria-label="Your groups">
          {groups.data.map((group) => (
            <li key={group.id}>
              <Link to={`/groups/${group.id}`}>{group.name}</Link>
            </li>
          ))}
        </ul>
      ) : groups.isSuccess ? (
        <p>You&rsquo;re not in any groups yet.</p>
      ) : null}

      <p>
        <Link to="/groups/new">Start a new group</Link>
      </p>

      <p>
        <Link to="/account">Account and email preferences</Link>
      </p>

      <button type="button" onClick={() => supabase.auth.signOut()}>
        Sign out
      </button>
    </main>
  );
}
