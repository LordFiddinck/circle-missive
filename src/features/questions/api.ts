import { supabase } from "@/lib/supabaseClient";
import type {
  CycleQuestion,
  Profile,
  QuestionProposal,
} from "@/lib/database.types";

export type ProposalWithAuthor = QuestionProposal & {
  author: Pick<Profile, "user_id" | "display_name"> | null;
};

/** A finalized question, with its (optional) public attribution resolved. */
export type CycleQuestionWithAsker = CycleQuestion & {
  asker: Pick<Profile, "user_id" | "display_name"> | null;
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
  showAuthor: boolean,
): Promise<QuestionProposal> {
  const { data, error } = await supabase
    .from("question_proposals")
    .insert({
      cycle_id: cycleId,
      author_id: authorId,
      text,
      show_author: showAuthor,
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateProposal(
  proposalId: string,
  changes: Partial<Pick<QuestionProposal, "text" | "show_author">>,
): Promise<QuestionProposal> {
  const { data, error } = await supabase
    .from("question_proposals")
    .update(changes)
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

/**
 * Organizer-only: opens answering with every suggestion, in the order
 * they were suggested. The one-click alternative to hand-picking.
 */
export async function releaseQuestions(cycleId: string) {
  const { data, error } = await supabase.rpc("release_questions", {
    p_cycle_id: cycleId,
  });
  if (error) throw error;
  return data;
}

export async function fetchCycleQuestions(
  cycleId: string,
): Promise<CycleQuestionWithAsker[]> {
  const { data, error } = await supabase
    .from("cycle_questions")
    .select("*, asker:profiles(user_id, display_name)")
    .eq("cycle_id", cycleId)
    .order("position", { ascending: true });
  if (error) throw error;
  return data as unknown as CycleQuestionWithAsker[];
}
