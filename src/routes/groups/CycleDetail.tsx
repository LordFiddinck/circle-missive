import { Link, useParams } from "react-router-dom";
import { useSession } from "@/lib/useSession";
import { useMembers } from "@/features/groups/queries";
import { useCycle } from "@/features/cycles/queries";
import { OrganizerProgress } from "@/features/cycles/OrganizerProgress";
import { QuestionWorkshop } from "@/features/questions/QuestionWorkshop";
import { AnswerEditor } from "@/features/answers/AnswerEditor";
import { IssueReader } from "@/features/issues/IssueReader";

const PHASE_LABELS: Record<string, string> = {
  question_collection: "Collecting questions",
  answering: "Open for answers",
  published: "Published",
  skipped: "Skipped",
};

export default function CycleDetail() {
  const { groupId, cycleId } = useParams<{
    groupId: string;
    cycleId: string;
  }>();
  const { session } = useSession();
  const cycle = useCycle(cycleId);
  const members = useMembers(groupId);

  if (!groupId || !cycleId || !session) {
    return null;
  }

  if (cycle.isLoading || members.isLoading) {
    return (
      <main>
        <p role="status">Loading cycle…</p>
      </main>
    );
  }

  if (cycle.isError || !cycle.data) {
    return (
      <main>
        <h1>Cycle not found</h1>
        <p>
          Either this cycle doesn&rsquo;t exist, or you&rsquo;re no longer a
          member of its group.
        </p>
      </main>
    );
  }

  const currentUserId = session.user.id;
  const isOrganizer = members.data?.some(
    (member) => member.user_id === currentUserId && member.role === "organizer",
  );

  const deadline =
    cycle.data.phase === "question_collection"
      ? cycle.data.question_closes_at
      : cycle.data.phase === "answering"
        ? cycle.data.answer_due_at
        : null;

  return (
    <main>
      <p>
        <Link to={`/groups/${groupId}`}>&larr; Back to group</Link>
      </p>
      <h1>Cycle #{cycle.data.sequence_no}</h1>
      <p>
        {PHASE_LABELS[cycle.data.phase] ?? cycle.data.phase}
        {deadline ? ` — due ${new Date(deadline).toLocaleString()}` : ""}
      </p>

      {cycle.data.phase === "question_collection" ? (
        <QuestionWorkshop
          groupId={groupId}
          cycleId={cycleId}
          currentUserId={currentUserId}
          isOrganizer={Boolean(isOrganizer)}
        />
      ) : null}

      {cycle.data.phase === "answering" ? (
        <AnswerEditor groupId={groupId} cycleId={cycleId} />
      ) : null}

      {cycle.data.phase === "published" ? (
        <IssueReader cycleId={cycleId} currentUserId={currentUserId} />
      ) : null}

      {cycle.data.phase === "skipped" ? (
        <p>This cycle was skipped — no issue was published for it.</p>
      ) : null}

      {isOrganizer &&
      (cycle.data.phase === "question_collection" ||
        cycle.data.phase === "answering") ? (
        <OrganizerProgress groupId={groupId} cycleId={cycleId} />
      ) : null}
    </main>
  );
}
