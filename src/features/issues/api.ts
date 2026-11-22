import { supabase } from "@/lib/supabaseClient";
import type { CycleQuestion, IssueEntry, Profile } from "@/lib/database.types";

export type IssueEntryWithDetails = IssueEntry & {
  author: Pick<Profile, "user_id" | "display_name"> | null;
  question: Pick<CycleQuestion, "id" | "text" | "position">;
};

/** A published cycle's entries, grouped question-first by the caller. */
export async function fetchIssueEntries(
  cycleId: string,
): Promise<IssueEntryWithDetails[]> {
  const { data, error } = await supabase
    .from("issue_entries")
    .select(
      "*, author:profiles(user_id, display_name), question:cycle_questions!inner(id, text, position)",
    )
    .eq("cycle_id", cycleId);
  if (error) throw error;

  // As with a member's own answers, ordering the embedded `question`
  // doesn't order these rows, so the API's order is arbitrary. Sort
  // explicitly: by question position, then by author name (then id) so
  // the people under each question never shuffle between loads.
  return (data as unknown as IssueEntryWithDetails[]).slice().sort((a, b) => {
    if (a.question.position !== b.question.position) {
      return a.question.position - b.question.position;
    }
    const byName = (a.author?.display_name ?? "").localeCompare(
      b.author?.display_name ?? "",
      undefined,
      { sensitivity: "base" },
    );
    return byName !== 0 ? byName : a.id.localeCompare(b.id);
  });
}
