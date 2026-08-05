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
    .eq("cycle_id", cycleId)
    .order("position", { referencedTable: "question" });
  if (error) throw error;
  return data as unknown as IssueEntryWithDetails[];
}
