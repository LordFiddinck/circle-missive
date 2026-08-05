import { supabase } from "@/lib/supabaseClient";
import type {
  CycleQuestion,
  Profile,
  QuestionProposal,
} from "@/lib/database.types";

export type ProposalWithAuthor = QuestionProposal & {
  author: Pick<Profile, "user_id" | "display_name"> | null;
};

/** Every proposal for a cycle, from every member — lets the group avoid duplicates. */
export async function fetchProposals(
  cycleId: string,
): Promise<ProposalWithAuthor[]> {
  const { data, error } = await supabase
    .from("question_proposals")
    .select("*, author:profiles(user_id, display_name)")
    .eq("cycle_id", cycleId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return data as unknown as ProposalWithAuthor[];
}

export async function createProposal(
  cycleId: string,
  authorId: string,
  text: string,
): Promise<QuestionProposal> {
  const { data, error } = await supabase
    .from("question_proposals")
    .insert({ cycle_id: cycleId, author_id: authorId, text })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateProposal(
  proposalId: string,
  text: string,
): Promise<QuestionProposal> {
  const { data, error } = await supabase
    .from("question_proposals")
    .update({ text })
    .eq("id", proposalId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function deleteProposal(proposalId: string): Promise<void> {
  const { error } = await supabase
    .from("question_proposals")
    .delete()
    .eq("id", proposalId);
  if (error) throw error;
}

/** Organizer-only: locks in an ordered set of proposals as the cycle's questions. */
export async function finalizeQuestions(
  cycleId: string,
  orderedProposalIds: string[],
) {
  const { data, error } = await supabase.rpc("finalize_questions", {
    p_cycle_id: cycleId,
    p_proposal_ids: orderedProposalIds,
  });
  if (error) throw error;
  return data;
}

export async function fetchCycleQuestions(
  cycleId: string,
): Promise<CycleQuestion[]> {
  const { data, error } = await supabase
    .from("cycle_questions")
    .select("*")
    .eq("cycle_id", cycleId)
    .order("position", { ascending: true });
  if (error) throw error;
  return data;
}
