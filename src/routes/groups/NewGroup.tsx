import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { useCreateGroup } from "@/features/groups/queries";

const DEFAULT_TIMEZONE =
  Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

export default function NewGroup() {
  const navigate = useNavigate();
  const createGroup = useCreateGroup();
  const [name, setName] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const group = await createGroup.mutateAsync({
      name: name.trim(),
      timezone: DEFAULT_TIMEZONE,
      intervalDays: 28,
      questionPhaseDays: 7,
      answerPhaseDays: 7,
    });
    navigate(`/groups/${group.id}`, { replace: true });
  }

  return (
    <main>
      <h1>Start a new group</h1>
      <p>
        You&rsquo;ll be its organizer. You can invite members and adjust cycle
        timing once it&rsquo;s created.
      </p>
      <form onSubmit={handleSubmit}>
        <label htmlFor="name">Group name</label>
        <input
          id="name"
          name="name"
          type="text"
          required
          minLength={1}
          maxLength={100}
          value={name}
          onChange={(event) => setName(event.target.value)}
        />
        <button
          type="submit"
          disabled={createGroup.isPending || name.trim() === ""}
        >
          {createGroup.isPending ? "Creating…" : "Create group"}
        </button>
      </form>
      {createGroup.isError ? (
        <p role="alert">
          Could not create the group:{" "}
          {createGroup.error instanceof Error
            ? createGroup.error.message
            : "Unknown error"}
        </p>
      ) : null}
    </main>
  );
}
