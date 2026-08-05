import { useState, type FormEvent } from "react";
import type { Profile } from "@/lib/database.types";
import { useUpdateMyProfile } from "./queries";

type DisplayNameFieldProps = {
  profile: Profile;
};

export function DisplayNameField({ profile }: DisplayNameFieldProps) {
  const updateProfile = useUpdateMyProfile(profile.user_id);
  const [editing, setEditing] = useState(profile.display_name.trim() === "");
  const [name, setName] = useState(profile.display_name);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await updateProfile.mutateAsync({ display_name: name.trim() });
    setEditing(false);
  }

  if (!editing) {
    return (
      <p>
        {profile.display_name}{" "}
        <button
          type="button"
          onClick={() => {
            setName(profile.display_name);
            setEditing(true);
          }}
        >
          Change
        </button>
      </p>
    );
  }

  return (
    <form onSubmit={handleSubmit}>
      <label htmlFor="display-name">
        Name (shown to other members of your groups)
      </label>
      <input
        id="display-name"
        name="display-name"
        type="text"
        required
        minLength={1}
        maxLength={80}
        value={name}
        onChange={(event) => setName(event.target.value)}
      />
      <button
        type="submit"
        disabled={updateProfile.isPending || name.trim() === ""}
      >
        {updateProfile.isPending ? "Saving…" : "Save"}
      </button>
      {profile.display_name.trim() !== "" ? (
        <button type="button" onClick={() => setEditing(false)}>
          Cancel
        </button>
      ) : null}
      {updateProfile.isError ? (
        <p role="alert">
          {updateProfile.error instanceof Error
            ? updateProfile.error.message
            : "Could not save your name."}
        </p>
      ) : null}
    </form>
  );
}
