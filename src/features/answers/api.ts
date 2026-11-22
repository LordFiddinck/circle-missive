import { supabase } from "@/lib/supabaseClient";
import type { Answer, CycleQuestion, Profile } from "@/lib/database.types";

export type AnswerWithQuestion = Answer & {
  question: Pick<CycleQuestion, "id" | "text" | "position" | "asked_by"> & {
    /** Present only when the proposer chose to show their name. */
    asker?: Pick<Profile, "user_id" | "display_name"> | null;
  };
};

/**
 * The signed-in member's own answers for a cycle, one per finalized
 * question. RLS already restricts `answers` to the caller's own rows,
 * so no explicit author filter is needed here.
 */
export async function fetchMyAnswers(
  cycleId: string,
): Promise<AnswerWithQuestion[]> {
  const { data, error } = await supabase
    .from("answers")
    .select(
      "*, question:cycle_questions!inner(id, text, position, asked_by, asker:profiles(user_id, display_name))",
    )
    .eq("question.cycle_id", cycleId);
  if (error) throw error;

  // Sort here, not in the query. PostgREST's `order(..., { referencedTable })`
  // only orders the embedded question *inside* each row — it never orders
  // the answer rows themselves, so the API returns them in physical
  // (heap) order. Every autosave UPDATE rewrites a row and moves it, which
  // is what made the questions reshuffle while people were typing.
  // `position` is unique per cycle, so this is a total, stable order.
  return (data as unknown as AnswerWithQuestion[])
    .slice()
    .sort((a, b) => a.question.position - b.question.position);
}

export async function saveAnswerDraft(
  answerId: string,
  body: string,
): Promise<Answer> {
  const { data, error } = await supabase
    .from("answers")
    .update({ body })
    .eq("id", answerId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function submitAnswers(cycleId: string): Promise<void> {
  const { error } = await supabase.rpc("submit_answers", {
    p_cycle_id: cycleId,
  });
  if (error) throw error;
}

/** Adds (or replaces) a member's answer to the published issue after the fact. */
export async function submitLateAnswer(
  questionId: string,
  body: string,
): Promise<void> {
  const { error } = await supabase.rpc("submit_late_answer", {
    p_question_id: questionId,
    p_body: body,
  });
  if (error) throw error;
}
