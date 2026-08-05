import { Link, useParams } from "react-router-dom";
import { useGroup } from "@/features/groups/queries";
import { Archive } from "@/features/issues/Archive";

export default function GroupArchive() {
  const { groupId } = useParams<{ groupId: string }>();
  const group = useGroup(groupId);

  if (!groupId) {
    return null;
  }

  return (
    <main>
      <p>
        <Link to={`/groups/${groupId}`}>&larr; Back to group</Link>
      </p>
      <h1>{group.data ? `${group.data.name} — archive` : "Archive"}</h1>
      <Archive groupId={groupId} />
    </main>
  );
}
