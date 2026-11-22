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
    <ul aria-label="Cycle archive" className="rows links">
      {cycles.data.map((cycle) => (
        <li key={cycle.id}>
          <Link to={`/groups/${groupId}/cycles/${cycle.id}`}>
            <span>Cycle #{cycle.sequence_no}</span>
            <span className="badge">
              {PHASE_LABELS[cycle.phase] ?? cycle.phase}
            </span>
            {cycle.published_at ? (
              <span className="muted">
                {new Date(cycle.published_at).toLocaleDateString()}
              </span>
            ) : null}
          </Link>
        </li>
      ))}
    </ul>
  );
}
