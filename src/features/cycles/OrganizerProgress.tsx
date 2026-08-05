import { useState, type FormEvent } from "react";
import {
  useChangeCycleDeadline,
  useCycle,
  useCycleProgress,
  usePublishCycle,
  useReopenSubmission,
  useSkipCycle,
} from "./queries";

type OrganizerProgressProps = {
  groupId: string;
  cycleId: string;
};

function toLocalDateTimeInputValue(iso: string): string {
  const date = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function OrganizerProgress({ groupId, cycleId }: OrganizerProgressProps) {
  const cycle = useCycle(cycleId);
  const progress = useCycleProgress(cycleId);
  const reopenSubmission = useReopenSubmission(cycleId);
  const changeDeadline = useChangeCycleDeadline(groupId, cycleId);
  const publishCycle = usePublishCycle(groupId, cycleId);
  const skipCycle = useSkipCycle(groupId, cycleId);

  const [newDeadline, setNewDeadline] = useState("");

  async function handleChangeDeadline(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!newDeadline) return;
    await changeDeadline.mutateAsync(new Date(newDeadline).toISOString());
    setNewDeadline("");
  }

  async function handlePublish() {
    const notSubmitted =
      progress.data?.filter((member) => !member.submitted).length ?? 0;
    const warning =
      notSubmitted > 0
        ? `${notSubmitted} member${notSubmitted === 1 ? " hasn't" : "s haven't"} submitted yet — their answers won't appear until they submit late. `
        : "";
    if (!window.confirm(`${warning}Publish this cycle's issue now?`)) return;
    await publishCycle.mutateAsync();
  }

  async function handleSkip() {
    if (
      !window.confirm(
        "Skip this cycle? No issue will be published for it, and this can't be undone.",
      )
    ) {
      return;
    }
    await skipCycle.mutateAsync();
  }

  if (progress.isLoading || cycle.isLoading) {
    return <p role="status">Loading progress…</p>;
  }

  if (progress.isError || cycle.isError || !cycle.data) {
    return <p role="alert">Could not load cycle progress.</p>;
  }

  const deadlineLabel =
    cycle.data.phase === "question_collection"
      ? cycle.data.question_closes_at
      : cycle.data.answer_due_at;

  return (
    <section aria-labelledby="organizer-progress-heading">
      <h2 id="organizer-progress-heading">Progress (organizer only)</h2>

      {cycle.data.phase === "answering" ? (
        <ul aria-label="Member completion">
          {progress.data?.map((member) => (
            <li key={member.user_id}>
              <span>
                {member.display_name} — {member.questions_answered}/
                {member.questions_total} answered
                {member.submitted ? ", submitted" : ""}
              </span>
              {member.submitted ? (
                <button
                  type="button"
                  onClick={() => {
                    if (
                      window.confirm(
                        `Reopen ${member.display_name}'s submission so they can revise it?`,
                      )
                    ) {
                      reopenSubmission.mutate(member.user_id);
                    }
                  }}
                  disabled={reopenSubmission.isPending}
                >
                  Reopen
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      ) : null}

      {deadlineLabel ? (
        <form onSubmit={handleChangeDeadline}>
          <label htmlFor="new-deadline">
            Change deadline (currently {new Date(deadlineLabel).toLocaleString()})
          </label>
          <input
            id="new-deadline"
            type="datetime-local"
            value={newDeadline || toLocalDateTimeInputValue(deadlineLabel)}
            onChange={(event) => setNewDeadline(event.target.value)}
          />
          <button type="submit" disabled={changeDeadline.isPending}>
            {changeDeadline.isPending ? "Saving…" : "Update deadline"}
          </button>
          {changeDeadline.isError ? (
            <p role="alert">
              {changeDeadline.error instanceof Error
                ? changeDeadline.error.message
                : "Could not update the deadline."}
            </p>
          ) : null}
        </form>
      ) : null}

      {cycle.data.phase === "answering" ? (
        <button
          type="button"
          onClick={handlePublish}
          disabled={publishCycle.isPending}
        >
          {publishCycle.isPending ? "Publishing…" : "Publish this issue now"}
        </button>
      ) : null}
      {publishCycle.isError ? (
        <p role="alert">
          {publishCycle.error instanceof Error
            ? publishCycle.error.message
            : "Could not publish this cycle."}
        </p>
      ) : null}

      <button type="button" onClick={handleSkip} disabled={skipCycle.isPending}>
        {skipCycle.isPending ? "Skipping…" : "Skip this cycle"}
      </button>
      {skipCycle.isError ? (
        <p role="alert">
          {skipCycle.error instanceof Error
            ? skipCycle.error.message
            : "Could not skip this cycle."}
        </p>
      ) : null}
    </section>
  );
}
