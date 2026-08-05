import { Link, useNavigate, useParams } from "react-router-dom";
import { useSession } from "@/lib/useSession";
import { GroupSettings } from "@/features/groups/GroupSettings";
import { InviteForm } from "@/features/groups/InviteForm";
import { InvitationList } from "@/features/groups/InvitationList";
import { MemberList } from "@/features/groups/MemberList";
import { useGroup, useLeaveGroup, useMembers } from "@/features/groups/queries";
import { useCurrentCycle, useStartCycle } from "@/features/cycles/queries";
import { EmailActivity } from "@/features/notifications/EmailActivity";

const PHASE_LABELS: Record<string, string> = {
  question_collection: "Collecting questions",
  answering: "Open for answers",
};

export default function GroupDetail() {
  const { groupId } = useParams<{ groupId: string }>();
  const navigate = useNavigate();
  const { session } = useSession();
  const group = useGroup(groupId);
  const members = useMembers(groupId);
  const leaveGroup = useLeaveGroup();
  const currentCycle = useCurrentCycle(groupId);
  const startCycle = useStartCycle(groupId ?? "");

  if (!groupId || !session) {
    return null;
  }

  if (group.isLoading || members.isLoading) {
    return (
      <main>
        <p role="status">Loading group…</p>
      </main>
    );
  }

  if (group.isError || !group.data) {
    return (
      <main>
        <h1>Group not found</h1>
        <p>
          Either this group doesn&rsquo;t exist, or you&rsquo;re no longer a
          member of it.
        </p>
      </main>
    );
  }

  const currentUserId = session.user.id;
  const myMembership = members.data?.find(
    (member) => member.user_id === currentUserId,
  );
  const isOrganizer = myMembership?.role === "organizer";

  async function handleLeave() {
    if (!window.confirm("Leave this group?")) return;
    await leaveGroup.mutateAsync(groupId as string);
    navigate("/", { replace: true });
  }

  return (
    <main>
      <GroupSettings group={group.data} />

      <section aria-labelledby="cycle-heading">
        <h2 id="cycle-heading">Current cycle</h2>
        {currentCycle.isLoading ? <p role="status">Loading…</p> : null}
        {currentCycle.isError ? (
          <p role="alert">Could not load this group&rsquo;s current cycle.</p>
        ) : null}
        {currentCycle.isSuccess && currentCycle.data ? (
          <p>
            <Link to={`/groups/${groupId}/cycles/${currentCycle.data.id}`}>
              Cycle #{currentCycle.data.sequence_no} —{" "}
              {PHASE_LABELS[currentCycle.data.phase] ?? currentCycle.data.phase}
            </Link>
          </p>
        ) : currentCycle.isSuccess ? (
          <>
            <p>No cycle is open right now.</p>
            {isOrganizer ? (
              <button
                type="button"
                onClick={() => startCycle.mutate()}
                disabled={startCycle.isPending}
              >
                {startCycle.isPending ? "Starting…" : "Start a new cycle"}
              </button>
            ) : null}
            {startCycle.isError ? (
              <p role="alert">
                {startCycle.error instanceof Error
                  ? startCycle.error.message
                  : "Could not start a new cycle."}
              </p>
            ) : null}
          </>
        ) : null}
        <p>
          <Link to={`/groups/${groupId}/archive`}>View past cycles</Link>
        </p>
      </section>

      <section aria-labelledby="members-heading">
        <h2 id="members-heading">Members</h2>
        <MemberList
          groupId={groupId}
          currentUserId={currentUserId}
          isOrganizer={isOrganizer}
        />
      </section>

      {isOrganizer ? (
        <section aria-labelledby="invitations-heading">
          <h2 id="invitations-heading">Invitations</h2>
          <InviteForm groupId={groupId} />
          <InvitationList groupId={groupId} />
        </section>
      ) : null}

      {isOrganizer ? (
        <section aria-labelledby="email-activity-heading">
          <h2 id="email-activity-heading">Email activity</h2>
          <EmailActivity groupId={groupId} />
        </section>
      ) : null}

      <section>
        <button
          type="button"
          onClick={handleLeave}
          disabled={leaveGroup.isPending}
        >
          {leaveGroup.isPending ? "Leaving…" : "Leave group"}
        </button>
        {leaveGroup.isError ? (
          <p role="alert">
            {leaveGroup.error instanceof Error
              ? leaveGroup.error.message
              : "Could not leave the group."}
          </p>
        ) : null}
      </section>
    </main>
  );
}
