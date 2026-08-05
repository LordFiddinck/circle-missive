import { Link } from "react-router-dom";
import { useCycles } from "@/features/cycles/queries";

type ArchiveProps = {
  groupId: string;
};

const PHASE_LABELS: Record<string, string> = {
  question_collection: "Collecting questions",
  answering: "Open for answers",
  published: "Published",
  skipped: "Skipped",
};

export function Archive({ groupId }: ArchiveProps) {
  const cycles = useCycles(groupId);

  if (cycles.isLoading) {
    return <p role="status">Loading past cycles…</p>;
  }

  if (cycles.isError) {
    return <p role="alert">Could not load past cycles.</p>;
  }

  if (!cycles.data || cycles.data.length === 0) {
    return <p>No cycles yet.</p>;
  }

  return (
    <ul aria-label="Cycle archive">
      {cycles.data.map((cycle) => (
        <li key={cycle.id}>
          <Link to={`/groups/${groupId}/cycles/${cycle.id}`}>
            Cycle #{cycle.sequence_no}
          </Link>{" "}
          — {PHASE_LABELS[cycle.phase] ?? cycle.phase}
          {cycle.published_at
            ? ` — published ${new Date(cycle.published_at).toLocaleDateString()}`
            : ""}
        </li>
      ))}
    </ul>
  );
}
