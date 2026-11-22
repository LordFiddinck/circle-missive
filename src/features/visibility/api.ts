import { supabase } from "@/lib/supabaseClient";
import type { AnswerVisibilityBlock } from "@/lib/database.types";

/** Organizer-only: RLS returns nothing to anyone else. */
export async function fetchAnswerBlocks(
  groupId: string,
): Promise<AnswerVisibilityBlock[]> {
  const { data, error } = await supabase
    .from("answer_visibility_blocks")
    .select("*")
    .eq("group_id", groupId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return data;
}

export async function hideAnswersBetween(
  groupId: string,
  userOne: string,
  userTwo: string,
): Promise<void> {
  const { error } = await supabase.rpc("hide_answers_between", {
    p_group_id: groupId,
    p_user_one: userOne,
    p_user_two: userTwo,
  });
  if (error) throw error;
}

export async function restoreAnswersBetween(
  groupId: string,
  userOne: string,
  userTwo: string,
): Promise<void> {
  const { error } = await supabase.rpc("restore_answers_between", {
    p_group_id: groupId,
    p_user_one: userOne,
    p_user_two: userTwo,
  });
  if (error) throw error;
}
