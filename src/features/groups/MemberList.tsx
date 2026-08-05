import { useMembers, useRemoveMember, useSetMemberRole } from "./queries";

type MemberListProps = {
  groupId: string;
  currentUserId: string;
  isOrganizer: boolean;
};

export function MemberList({
  groupId,
  currentUserId,
  isOrganizer,
}: MemberListProps) {
  const members = useMembers(groupId);
  const removeMember = useRemoveMember(groupId);
  const setMemberRole = useSetMemberRole(groupId);

  if (members.isLoading) {
    return <p role="status">Loading members…</p>;
  }

  if (members.isError) {
    return <p role="alert">Could not load members.</p>;
  }

  return (
    <ul aria-label="Members">
      {members.data?.map((member) => {
        const label = member.profile?.display_name || "(no name set)";
        const isSelf = member.user_id === currentUserId;
        return (
          <li key={member.id}>
            <span>
              {label} {isSelf ? "(you)" : ""} — {member.role}
            </span>
            {isOrganizer && !isSelf ? (
              <>
                <button
                  type="button"
                  onClick={() =>
                    setMemberRole.mutate({
                      userId: member.user_id,
                      role:
                        member.role === "organizer" ? "member" : "organizer",
                    })
                  }
                  disabled={setMemberRole.isPending}
                >
                  {member.role === "organizer"
                    ? "Make member"
                    : "Make organizer"}
                </button>
                <button
                  type="button"
                  onClick={() => {
                    if (window.confirm(`Remove ${label} from the group?`)) {
                      removeMember.mutate(member.user_id);
                    }
                  }}
                  disabled={removeMember.isPending}
                >
                  Remove
                </button>
              </>
            ) : null}
          </li>
        );
      })}
      {(removeMember.isError || setMemberRole.isError) && (
        <p role="alert">
          {removeMember.error instanceof Error
            ? removeMember.error.message
            : setMemberRole.error instanceof Error
              ? setMemberRole.error.message
              : "That change couldn't be made."}
        </p>
      )}
    </ul>
  );
}
