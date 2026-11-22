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
  /** Lets the editor force any pending autosave to finish before submitting. */
  registerFlush: (
    answerId: string,
    flush: (() => Promise<void>) | null,
  ) => void;
};

function AnswerField({
  answer,
  index,
  onSave,
  onFilledChange,
  registerFlush,
}: AnswerFieldProps) {
  const [value, setValue] = useState(answer.body);
  const [status, setStatus] = useState<SaveStatus>("idle");
  const [recovered, setRecovered] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const valueRef = useRef(value);
  const dirtyRef = useRef(false);
  const onSaveRef = useRef(onSave);
  const isSubmitted = answer.submitted_at !== null;

  valueRef.current = value;
  onSaveRef.current = onSave;

  // Saves anything typed but not yet persisted, immediately. Submitting
  // runs this first: the autosave is debounced, and a submitted answer
  // can no longer be edited, so text typed in the last moments before
  // pressing Submit would otherwise be lost.
  const flush = useCallback(async () => {
    if (debounceRef.current) {
      clearTimeout(debounceRef.current);
      debounceRef.current = null;
    }
    if (!dirtyRef.current) return;
    const toSave = valueRef.current;
    setStatus("saving");
    try {
      await onSaveRef.current(answer.id, toSave);
    } catch (error) {
      setStatus("error");
      throw error;
    }
    if (valueRef.current === toSave) {
      dirtyRef.current = false;
      window.localStorage.removeItem(draftStorageKey(answer.id));
    }
    setStatus("saved");
  }, [answer.id]);

  useEffect(() => {
    registerFlush(answer.id, flush);
    return () => registerFlush(answer.id, null);
  }, [answer.id, flush, registerFlush]);

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
      dirtyRef.current = true;
      onSave(answer.id, saved)
        .then(() => {
          if (valueRef.current === saved) dirtyRef.current = false;
          setStatus("saved");
        })
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
    valueRef.current = nextValue;
    dirtyRef.current = true;
    window.localStorage.setItem(draftStorageKey(answer.id), nextValue);
    setStatus("saving");

    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      onSave(answer.id, nextValue)
        .then(() => {
          // Only treat it as clean if nothing newer was typed meanwhile.
          if (valueRef.current === nextValue) {
            dirtyRef.current = false;
            window.localStorage.removeItem(draftStorageKey(answer.id));
            setStatus("saved");
          }
        })
        .catch(() => setStatus("error"));
    }, AUTOSAVE_DELAY_MS);
  }

  function handleRetry() {
    dirtyRef.current = true;
    flush().catch(() => undefined);
  }

  const fieldId = `answer-${answer.id}`;
  const wordCount = value.trim() === "" ? 0 : value.trim().split(/\s+/).length;

  return (
    <section aria-labelledby={`${fieldId}-label`} className="question">
      <h3 id={`${fieldId}-label`}>
        <span className="q-num">{index + 1}.</span> {answer.question.text}
      </h3>
      {answer.question.asker?.display_name ? (
        <p className="question-asker">
          Asked by {answer.question.asker.display_name}
        </p>
      ) : null}
      {recovered ? (
        <p role="status">Recovered a draft you hadn&rsquo;t finished saving.</p>
      ) : null}
      <label htmlFor={fieldId} className="sr-only">
        Your answer to: {answer.question.text}
      </label>
      <textarea
        id={fieldId}
        className="answer-input"
        value={value}
        onChange={(event) => handleChange(event.target.value)}
        disabled={isSubmitted}
        maxLength={20000}
        rows={6}
      />
      <div className="field-meta">
        <p>
          {wordCount} word{wordCount === 1 ? "" : "s"}
        </p>
        {isSubmitted ? (
          <p role="status">
            {answer.body.trim() === ""
              ? "Left blank — you can still add it once the issue is published."
              : "Submitted."}
          </p>
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
      </div>
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
  const [flushError, setFlushError] = useState(false);
  const flushers = useRef(new Map<string, () => Promise<void>>());

  const registerFlush = useCallback(
    (answerId: string, flush: (() => Promise<void>) | null) => {
      if (flush) flushers.current.set(answerId, flush);
      else flushers.current.delete(answerId);
    },
    [],
  );

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
  const isFilled = (item: AnswerWithQuestion) =>
    filledOverrides[item.id] ?? item.body.trim() !== "";
  const filledCount = items.filter(isFilled).length;
  const blankCount = items.length - filledCount;
  // Partial submissions are allowed: one answer is enough to submit.
  const canSubmit = filledCount > 0;

  async function handleSubmit() {
    const blankNote =
      blankCount > 0
        ? `${blankCount} of ${items.length} question${items.length === 1 ? " is" : "s are"} still blank — those won't appear in the issue, though you can add them after it's published. `
        : "";
    if (
      !window.confirm(
        `${blankNote}Submit your answers? You won't be able to edit them again unless the organizer reopens them.`,
      )
    ) {
      return;
    }
    setFlushError(false);
    try {
      await Promise.all([...flushers.current.values()].map((flush) => flush()));
    } catch {
      setFlushError(true);
      return;
    }
    await submitAnswers.mutateAsync();
  }

  return (
    <div>
      {allSubmitted ? null : (
        <p>
          Answer as many questions as you like. Anything you&rsquo;ve saved is
          submitted for you automatically when the cycle closes.
        </p>
      )}
      {items.map((answer, index) => (
        <AnswerField
          key={answer.id}
          answer={answer}
          index={index}
          onSave={handleSave}
          onFilledChange={handleFilledChange}
          registerFlush={registerFlush}
        />
      ))}

      {allSubmitted ? (
        <p>You&rsquo;ve submitted all your answers for this cycle.</p>
      ) : (
        <>
          <div className="actions">
            <button
              type="button"
              className="primary"
              onClick={handleSubmit}
              disabled={!canSubmit || submitAnswers.isPending}
            >
              {submitAnswers.isPending ? "Submitting…" : "Submit answers"}
            </button>
          </div>
          {!canSubmit ? <p>Answer at least one question to submit.</p> : null}
          {flushError ? (
            <p role="alert">
              Your latest changes couldn&rsquo;t be saved, so nothing was
              submitted. Check your connection and try again.
            </p>
          ) : null}
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
