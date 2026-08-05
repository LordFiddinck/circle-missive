import { useState, type FormEvent } from "react";
import {
  useCreateProposal,
  useDeleteProposal,
  useFinalizeQuestions,
  useProposals,
  useUpdateProposal,
} from "./queries";

type QuestionWorkshopProps = {
  groupId: string;
  cycleId: string;
  currentUserId: string;
  isOrganizer: boolean;
};

export function QuestionWorkshop({
  groupId,
  cycleId,
  currentUserId,
  isOrganizer,
}: QuestionWorkshopProps) {
  const proposals = useProposals(cycleId);
  const createProposal = useCreateProposal(cycleId, currentUserId);
  const updateProposal = useUpdateProposal(cycleId);
  const deleteProposal = useDeleteProposal(cycleId);
  const finalizeQuestions = useFinalizeQuestions(groupId, cycleId);

  const [newText, setNewText] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editingText, setEditingText] = useState("");
  const [selectedIds, setSelectedIds] = useState<string[]>([]);

  async function handlePropose(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await createProposal.mutateAsync(newText.trim());
    setNewText("");
  }

  async function handleSaveEdit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!editingId) return;
    await updateProposal.mutateAsync({ id: editingId, text: editingText.trim() });
    setEditingId(null);
  }

  function toggleSelected(proposalId: string) {
    setSelectedIds((current) =>
      current.includes(proposalId)
        ? current.filter((id) => id !== proposalId)
        : [...current, proposalId],
    );
  }

  function moveSelected(index: number, direction: -1 | 1) {
    setSelectedIds((current) => {
      const next = [...current];
      const target = index + direction;
      if (target < 0 || target >= next.length) return current;
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
  }

  async function handleFinalize() {
    if (selectedIds.length === 0) return;
    if (
      !window.confirm(
        `Finalize these ${selectedIds.length} question${selectedIds.length === 1 ? "" : "s"}? Members will start answering them right away, and no more suggestions can be added.`,
      )
    ) {
      return;
    }
    await finalizeQuestions.mutateAsync(selectedIds);
  }

  if (proposals.isLoading) {
    return <p role="status">Loading suggested questions…</p>;
  }

  if (proposals.isError) {
    return <p role="alert">Could not load suggested questions.</p>;
  }

  const items = proposals.data ?? [];
  const selectedProposals = selectedIds
    .map((id) => items.find((item) => item.id === id))
    .filter((item): item is NonNullable<typeof item> => Boolean(item));

  return (
    <div>
      <form onSubmit={handlePropose}>
        <label htmlFor="new-proposal">Suggest a question</label>
        <input
          id="new-proposal"
          name="new-proposal"
          type="text"
          required
          minLength={1}
          maxLength={500}
          value={newText}
          onChange={(event) => setNewText(event.target.value)}
        />
        <button
          type="submit"
          disabled={createProposal.isPending || newText.trim() === ""}
        >
          {createProposal.isPending ? "Adding…" : "Add suggestion"}
        </button>
        {createProposal.isError ? (
          <p role="alert">Could not add that suggestion.</p>
        ) : null}
      </form>

      <h3>Suggestions</h3>
      {items.length === 0 ? (
        <p>No one has suggested a question yet.</p>
      ) : (
        <ul aria-label="Suggested questions">
          {items.map((proposal) => {
            const isOwn = proposal.author_id === currentUserId;
            const isEditing = editingId === proposal.id;
            return (
              <li key={proposal.id}>
                {isEditing ? (
                  <form onSubmit={handleSaveEdit}>
                    <label htmlFor={`edit-${proposal.id}`}>Edit suggestion</label>
                    <input
                      id={`edit-${proposal.id}`}
                      type="text"
                      required
                      minLength={1}
                      maxLength={500}
                      value={editingText}
                      onChange={(event) => setEditingText(event.target.value)}
                    />
                    <button
                      type="submit"
                      disabled={
                        updateProposal.isPending || editingText.trim() === ""
                      }
                    >
                      Save
                    </button>
                    <button type="button" onClick={() => setEditingId(null)}>
                      Cancel
                    </button>
                  </form>
                ) : (
                  <>
                    <span>
                      {proposal.text} —{" "}
                      {proposal.author?.display_name || "(no name set)"}
                      {isOwn ? " (you)" : ""}
                    </span>
                    {isOwn ? (
                      <>
                        <button
                          type="button"
                          onClick={() => {
                            setEditingId(proposal.id);
                            setEditingText(proposal.text);
                          }}
                        >
                          Edit
                        </button>
                        <button
                          type="button"
                          onClick={() => {
                            if (window.confirm("Remove this suggestion?")) {
                              deleteProposal.mutate(proposal.id);
                              setSelectedIds((current) =>
                                current.filter((id) => id !== proposal.id),
                              );
                            }
                          }}
                        >
                          Remove
                        </button>
                      </>
                    ) : null}
                    {isOrganizer ? (
                      <button
                        type="button"
                        onClick={() => toggleSelected(proposal.id)}
                        aria-pressed={selectedIds.includes(proposal.id)}
                      >
                        {selectedIds.includes(proposal.id)
                          ? "Selected"
                          : "Select for this cycle"}
                      </button>
                    ) : null}
                  </>
                )}
              </li>
            );
          })}
        </ul>
      )}

      {isOrganizer ? (
        <section aria-labelledby="final-questions-heading">
          <h3 id="final-questions-heading">Final questions for this cycle</h3>
          {selectedProposals.length === 0 ? (
            <p>Select suggestions above to build the final, ordered list.</p>
          ) : (
            <ol aria-label="Selected questions, in answering order">
              {selectedProposals.map((proposal, index) => (
                <li key={proposal.id}>
                  {proposal.text}
                  <button
                    type="button"
                    onClick={() => moveSelected(index, -1)}
                    disabled={index === 0}
                  >
                    Move up
                  </button>
                  <button
                    type="button"
                    onClick={() => moveSelected(index, 1)}
                    disabled={index === selectedProposals.length - 1}
                  >
                    Move down
                  </button>
                  <button type="button" onClick={() => toggleSelected(proposal.id)}>
                    Remove
                  </button>
                </li>
              ))}
            </ol>
          )}
          <button
            type="button"
            onClick={handleFinalize}
            disabled={selectedIds.length === 0 || finalizeQuestions.isPending}
          >
            {finalizeQuestions.isPending
              ? "Finalizing…"
              : `Finalize ${selectedIds.length || ""} question${selectedIds.length === 1 ? "" : "s"} and open answering`}
          </button>
          {finalizeQuestions.isError ? (
            <p role="alert">
              {finalizeQuestions.error instanceof Error
                ? finalizeQuestions.error.message
                : "Could not finalize these questions."}
            </p>
          ) : null}
        </section>
      ) : null}
    </div>
  );
}
