import { useCallback, useEffect, useRef, useState } from "react";
import type { AnswerWithQuestion } from "./api";
import { useMyAnswers, useSaveAnswerDraft, useSubmitAnswers } from "./queries";

const AUTOSAVE_DELAY_MS = 800;

function draftStorageKey(answerId: string): string {
  return `circle-missive:answer-draft:${answerId}`;
}

type SaveStatus = "idle" | "saving" | "saved" | "error";

type AnswerFieldProps = {
  answer: AnswerWithQuestion;
  index: number;
  onSave: (answerId: string, body: string) => Promise<unknown>;
  onFilledChange: (answerId: string, filled: boolean) => void;
};

function AnswerField({
  answer,
  index,
  onSave,
  onFilledChange,
}: AnswerFieldProps) {
  const [value, setValue] = useState(answer.body);
  const [status, setStatus] = useState<SaveStatus>("idle");
  const [recovered, setRecovered] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isSubmitted = answer.submitted_at !== null;

  // Report fill state up to the parent on every change (including the
  // initial value) so the Submit button reflects what's on screen right
  // now, not whichever body was last successfully saved to the server —
  // autosave is debounced, and the two can lag behind each other by
  // up to AUTOSAVE_DELAY_MS.
  useEffect(() => {
    onFilledChange(answer.id, value.trim() !== "");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);

  // On mount, prefer a local recovery copy over the server body if one
  // exists and differs — this is what makes a lost connection or a
  // refresh mid-sentence non-destructive (see implementation plan,
  // "the answer editor must tolerate a temporary connection loss").
  useEffect(() => {
    if (isSubmitted) return;
    const saved = window.localStorage.getItem(draftStorageKey(answer.id));
    if (saved !== null && saved !== answer.body) {
      setValue(saved);
      setRecovered(true);
      setStatus("saving");
      onSave(answer.id, saved)
        .then(() => setStatus("saved"))
        .catch(() => setStatus("error"));
    }
    // Only ever run this recovery check once, right after mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, []);

  function handleChange(nextValue: string) {
    setValue(nextValue);
    window.localStorage.setItem(draftStorageKey(answer.id), nextValue);
    setStatus("saving");

    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      onSave(answer.id, nextValue)
        .then(() => {
          setStatus("saved");
          window.localStorage.removeItem(draftStorageKey(answer.id));
        })
        .catch(() => setStatus("error"));
    }, AUTOSAVE_DELAY_MS);
  }

  function handleRetry() {
    setStatus("saving");
    onSave(answer.id, value)
      .then(() => {
        setStatus("saved");
        window.localStorage.removeItem(draftStorageKey(answer.id));
      })
      .catch(() => setStatus("error"));
  }

  const fieldId = `answer-${answer.id}`;
  const wordCount = value.trim() === "" ? 0 : value.trim().split(/\s+/).length;

  return (
    <section aria-labelledby={`${fieldId}-label`}>
      <h3 id={`${fieldId}-label`}>
        {index + 1}. {answer.question.text}
      </h3>
      {recovered ? (
        <p role="status">Recovered a draft you hadn&rsquo;t finished saving.</p>
      ) : null}
      <label htmlFor={fieldId} className="sr-only">
        Your answer to: {answer.question.text}
      </label>
      <textarea
        id={fieldId}
        value={value}
        onChange={(event) => handleChange(event.target.value)}
        disabled={isSubmitted}
        maxLength={20000}
        rows={6}
      />
      <p>
        {wordCount} word{wordCount === 1 ? "" : "s"}
      </p>
      {isSubmitted ? (
        <p role="status">Submitted.</p>
      ) : (
        <p role="status" aria-live="polite">
          {status === "saving"
            ? "Saving…"
            : status === "saved"
              ? "Saved"
              : status === "error"
                ? "Could not save"
                : null}
          {status === "error" ? (
            <button type="button" onClick={handleRetry}>
              Retry
            </button>
          ) : null}
        </p>
      )}
    </section>
  );
}

type AnswerEditorProps = {
  groupId: string;
  cycleId: string;
};

export function AnswerEditor({ groupId, cycleId }: AnswerEditorProps) {
  const answers = useMyAnswers(cycleId);
  const saveDraft = useSaveAnswerDraft(cycleId);
  const submitAnswers = useSubmitAnswers(groupId, cycleId);
  const [filledOverrides, setFilledOverrides] = useState<
    Record<string, boolean>
  >({});

  const handleFilledChange = useCallback(
    (answerId: string, filled: boolean) => {
      setFilledOverrides((current) =>
        current[answerId] === filled
          ? current
          : { ...current, [answerId]: filled },
      );
    },
    [],
  );

  async function handleSave(answerId: string, body: string) {
    return saveDraft.mutateAsync({ answerId, body });
  }

  if (answers.isLoading) {
    return <p role="status">Loading the answer editor…</p>;
  }

  if (answers.isError) {
    return <p role="alert">Could not load your answers.</p>;
  }

  const items = answers.data ?? [];
  const allSubmitted = items.length > 0 && items.every((a) => a.submitted_at);
  const allFilled = items.every(
    (item) => filledOverrides[item.id] ?? item.body.trim() !== "",
  );

  async function handleSubmit() {
    if (
      !window.confirm(
        "Submit your answers? You won't be able to edit them again unless the organizer reopens them.",
      )
    ) {
      return;
    }
    await submitAnswers.mutateAsync();
  }

  return (
    <div>
      {items.map((answer, index) => (
        <AnswerField
          key={answer.id}
          answer={answer}
          index={index}
          onSave={handleSave}
          onFilledChange={handleFilledChange}
        />
      ))}

      {allSubmitted ? (
        <p>You&rsquo;ve submitted all your answers for this cycle.</p>
      ) : (
        <>
          <button
            type="button"
            onClick={handleSubmit}
            disabled={!allFilled || submitAnswers.isPending}
          >
            {submitAnswers.isPending ? "Submitting…" : "Submit answers"}
          </button>
          {!allFilled ? <p>Answer every question before submitting.</p> : null}
          {submitAnswers.isError ? (
            <p role="alert">
              {submitAnswers.error instanceof Error
                ? submitAnswers.error.message
                : "Could not submit your answers."}
            </p>
          ) : null}
        </>
      )}
    </div>
  );
}
