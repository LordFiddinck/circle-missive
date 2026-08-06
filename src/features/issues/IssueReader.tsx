import { useState, type FormEvent } from "react";
import { useCycleQuestions } from "@/features/questions/queries";
import { useSubmitLateAnswer } from "@/features/answers/queries";
import { useIssueEntries } from "./queries";

type IssueReaderProps = {
  cycleId: string;
  currentUserId: string;
};

function LateAnswerForm({
  cycleId,
  questionId,
  questionText,
}: {
  cycleId: string;
  questionId: string;
  questionText: string;
}) {
  const submitLateAnswer = useSubmitLateAnswer(cycleId);
  const [body, setBody] = useState("");
  const [open, setOpen] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await submitLateAnswer.mutateAsync({ questionId, body: body.trim() });
    setBody("");
    setOpen(false);
  }

  if (!open) {
    return (
      <p>
        You haven&rsquo;t answered this one yet.{" "}
        <button type="button" onClick={() => setOpen(true)}>
          Add your answer
        </button>
      </p>
    );
  }

  return (
    <form onSubmit={handleSubmit}>
      <label htmlFor={`late-${questionId}`}>
        Your (late) answer to: {questionText}
      </label>
      <textarea
        id={`late-${questionId}`}
        value={body}
        onChange={(event) => setBody(event.target.value)}
        maxLength={20000}
        rows={4}
        required
      />
      <button
        type="submit"
        disabled={submitLateAnswer.isPending || body.trim() === ""}
      >
        {submitLateAnswer.isPending ? "Adding…" : "Add answer"}
      </button>
      <button type="button" onClick={() => setOpen(false)}>
        Cancel
      </button>
      {submitLateAnswer.isError ? (
        <p role="alert">
          {submitLateAnswer.error instanceof Error
            ? submitLateAnswer.error.message
            : "Could not add your answer."}
        </p>
      ) : null}
    </form>
  );
}

export function IssueReader({ cycleId, currentUserId }: IssueReaderProps) {
  const entries = useIssueEntries(cycleId);
  const questions = useCycleQuestions(cycleId);

  if (entries.isLoading || questions.isLoading) {
    return <p role="status">Loading this issue…</p>;
  }

  if (entries.isError || questions.isError) {
    return <p role="alert">Could not load this issue.</p>;
  }

  const allQuestions = questions.data ?? [];
  const allEntries = entries.data ?? [];

  return (
    <div>
      {allQuestions.map((question) => {
        const questionEntries = allEntries.filter(
          (entry) => entry.question_id === question.id,
        );
        const hasOwnEntry = questionEntries.some(
          (entry) => entry.author_id === currentUserId,
        );
        return (
          <section key={question.id} aria-labelledby={`issue-q-${question.id}`}>
            <h3 id={`issue-q-${question.id}`}>{question.text}</h3>
            {questionEntries.length === 0 ? (
              <p>No one answered this one.</p>
            ) : (
              <dl>
                {questionEntries.map((entry) => (
                  <div key={entry.id}>
                    <dt>
                      {entry.author?.display_name || "(no name set)"}
                      {entry.is_late ? " (added later)" : ""}
                    </dt>
                    <dd style={{ whiteSpace: "pre-wrap" }}>{entry.body}</dd>
                  </div>
                ))}
              </dl>
            )}
            {!hasOwnEntry ? (
              <LateAnswerForm
                cycleId={cycleId}
                questionId={question.id}
                questionText={question.text}
              />
            ) : null}
          </section>
        );
      })}
    </div>
  );
}
