/**
 * A human-readable message from anything that was thrown or returned as
 * an error, or `fallback` when there isn't one.
 *
 * This exists because the Supabase client returns database errors
 * (including the messages our own SQL functions raise on purpose, such as
 * "Only an organizer can release questions.") as plain objects shaped like
 * `{ message, code, details, hint }` — they are NOT `Error` instances, so
 * `error instanceof Error` is false for them. Auth and Storage errors, on
 * the other hand, are real `Error`s. Checking for a string `message`
 * handles both.
 */
export function errorMessage(error: unknown, fallback: string): string {
  if (typeof error === "string" && error.trim() !== "") return error;

  if (typeof error === "object" && error !== null && "message" in error) {
    const message = (error as { message: unknown }).message;
    if (typeof message === "string" && message.trim() !== "") return message;
  }

  return fallback;
}
