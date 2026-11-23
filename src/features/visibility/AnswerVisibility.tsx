import { useState, type FormEvent } from "react";
import { useMembers } from "@/features/groups/queries";
import { useAnswerBlocks, useHideAnswers, useRestoreAnswers } from "./queries";
import { errorMessage } from "@/lib/errorMessage";

type AnswerVisibilityProps = {
  groupId: string;
};

/**
 * Organizer-only control for keeping two members from reading each
 * other's answers in published issues.
 */
export function AnswerVisibility({ groupId }: AnswerVisibilityProps) {
  const members = useMembers(groupId);
  const blocks = useAnswerBlocks(groupId);
  const hideAnswers = useHideAnswers(groupId);
  const restoreAnswers = useRestoreAnswers(groupId);
  const [first, setFirst] = useState("");
  const [second, setSecond] = useState("");

  const people = members.data ?? [];
  const nameOf = (userId: string) => {
    const member = people.find((candidate) => candidate.user_id === userId);
    // Blocks outlive membership, so a pair can include someone who left.
    if (!member) return "A former member";
    return member.profile?.display_name || "(no name set)";
  };

  const alreadyHidden =
    first !== "" &&
    second !== "" &&
    (blocks.data ?? []).some(
      (block) =>
        (block.user_a === first && block.user_b === second) ||
        (block.user_a === second && block.user_b === first),
    );
  const canSubmit =
    first !== "" && second !== "" && first !== second && !alreadyHidden;

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!canSubmit) return;
    await hideAnswers.mutateAsync({ userOne: first, userTwo: second });
    setFirst("");
    setSecond("");
  }

  if (members.isLoading || blocks.isLoading) {
    return <p role="status">Loading…</p>;
  }

  if (blocks.isError) {
    return <p role="alert">Could not load answer visibility settings.</p>;
  }

  return (
    <div>
      <p>
        Choose two people who shouldn&rsquo;t read each other&rsquo;s answers.
        Neither will see the other&rsquo;s answers in any issue, past or future,
        and they won&rsquo;t be told. They still see everyone else&rsquo;s
        answers. Only organizers can see this list.
      </p>

      <form onSubmit={handleSubmit}>
        <div className="pair">
          <div>
            <label htmlFor="hide-first">First person</label>
            <select
              id="hide-first"
              value={first}
              onChange={(event) => setFirst(event.target.value)}
            >
              <option value="">Choose a member…</option>
              {people.map((member) => (
                <option
                  key={member.user_id}
                  value={member.user_id}
                  disabled={member.user_id === second}
                >
                  {member.profile?.display_name || "(no name set)"}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="hide-second">Second person</label>
            <select
              id="hide-second"
              value={second}
              onChange={(event) => setSecond(event.target.value)}
            >
              <option value="">Choose a member…</option>
              {people.map((member) => (
                <option
                  key={member.user_id}
                  value={member.user_id}
                  disabled={member.user_id === first}
                >
                  {member.profile?.display_name || "(no name set)"}
                </option>
              ))}
            </select>
          </div>
        </div>

        <button type="submit" disabled={!canSubmit || hideAnswers.isPending}>
          {hideAnswers.isPending
            ? "Saving…"
            : "Hide their answers from each other"}
        </button>
        {alreadyHidden ? (
          <p>These two are already hidden from each other.</p>
        ) : null}
        {hideAnswers.isError ? (
          <p role="alert">
            {errorMessage(hideAnswers.error, "Could not save this change.")}
          </p>
        ) : null}
      </form>

      {blocks.data && blocks.data.length > 0 ? (
        <ul aria-label="Hidden pairs" className="rows">
          {blocks.data.map((block) => (
            <li key={block.id}>
              <span className="row-main">
                {nameOf(block.user_a)} and {nameOf(block.user_b)} can&rsquo;t
                see each other&rsquo;s answers
              </span>
              <button
                type="button"
                disabled={restoreAnswers.isPending}
                onClick={() => {
                  if (
                    window.confirm(
                      `Let ${nameOf(block.user_a)} and ${nameOf(block.user_b)} see each other's answers again? This also restores past issues.`,
                    )
                  ) {
                    restoreAnswers.mutate({
                      userOne: block.user_a,
                      userTwo: block.user_b,
                    });
                  }
                }}
              >
                Allow again
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p>No one is hidden from anyone right now.</p>
      )}
      {restoreAnswers.isError ? (
        <p role="alert">
          {errorMessage(restoreAnswers.error, "Could not save this change.")}
        </p>
      ) : null}
    </div>
  );
}
