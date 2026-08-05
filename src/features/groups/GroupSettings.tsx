import { useState, type FormEvent } from "react";
import type { Group } from "@/lib/database.types";
import { useUpdateGroup } from "./queries";

type GroupSettingsProps = {
  group: Group;
};

export function GroupSettings({ group }: GroupSettingsProps) {
  const updateGroup = useUpdateGroup(group.id);
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(group.name);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await updateGroup.mutateAsync({ name: name.trim() });
    setEditing(false);
  }

  if (!editing) {
    return (
      <p>
        {group.name}{" "}
        <button
          type="button"
          onClick={() => {
            setName(group.name);
            setEditing(true);
          }}
        >
          Rename
        </button>
      </p>
    );
  }

  return (
    <form onSubmit={handleSubmit}>
      <label htmlFor="group-name">Group name</label>
      <input
        id="group-name"
        name="group-name"
        type="text"
        required
        minLength={1}
        maxLength={100}
        value={name}
        onChange={(event) => setName(event.target.value)}
      />
      <button
        type="submit"
        disabled={updateGroup.isPending || name.trim() === ""}
      >
        {updateGroup.isPending ? "Saving…" : "Save"}
      </button>
      <button type="button" onClick={() => setEditing(false)}>
        Cancel
      </button>
      {updateGroup.isError ? (
        <p role="alert">
          {updateGroup.error instanceof Error
            ? updateGroup.error.message
            : "Could not save."}
        </p>
      ) : null}
    </form>
  );
}
