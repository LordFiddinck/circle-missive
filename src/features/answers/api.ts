import { supabase } from "@/lib/supabaseClient";
import type { Answer, CycleQuestion } from "@/lib/database.types";

export type AnswerWithQuestion = Answer & {
  question: Pick<CycleQuestion, "id" | "text" | "position">;
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
    .select("*, question:cycle_questions!inner(id, text, position)")
    .eq("question.cycle_id", cycleId)
    .order("position", { referencedTable: "question" });
  if (error) throw error;
  return data as unknown as AnswerWithQuestion[];
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
