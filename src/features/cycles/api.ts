import { supabase } from "@/lib/supabaseClient";
import type { Cycle, CycleProgress } from "@/lib/database.types";

/** All cycles for a group, newest first — used by the archive screen. */
export async function fetchCycles(groupId: string): Promise<Cycle[]> {
  const { data, error } = await supabase
    .from("cycles")
    .select("*")
    .eq("group_id", groupId)
    .order("sequence_no", { ascending: false });
  if (error) throw error;
  return data;
}

/** The one cycle (if any) currently open for question collection or answering. */
export async function fetchCurrentCycle(
  groupId: string,
): Promise<Cycle | null> {
  const { data, error } = await supabase
    .from("cycles")
    .select("*")
    .eq("group_id", groupId)
    .in("phase", ["question_collection", "answering"])
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function fetchCycle(cycleId: string): Promise<Cycle> {
  const { data, error } = await supabase
    .from("cycles")
    .select("*")
    .eq("id", cycleId)
    .single();
  if (error) throw error;
  return data;
}

export async function startCycle(groupId: string): Promise<Cycle> {
  const { data, error } = await supabase.rpc("start_cycle", {
    p_group_id: groupId,
  });
  if (error) throw error;
  return data;
}

export async function skipCycle(cycleId: string): Promise<Cycle> {
  const { data, error } = await supabase.rpc("skip_cycle", {
    p_cycle_id: cycleId,
  });
  if (error) throw error;
  return data;
}

export async function changeCycleDeadline(
  cycleId: string,
  newDueAt: string,
): Promise<Cycle> {
  const { data, error } = await supabase.rpc("change_cycle_deadline", {
    p_cycle_id: cycleId,
    p_new_due_at: newDueAt,
  });
  if (error) throw error;
  return data;
}

export async function publishCycle(cycleId: string): Promise<Cycle> {
  const { data, error } = await supabase.rpc("publish_cycle", {
    p_cycle_id: cycleId,
  });
  if (error) throw error;
  return data;
}

/** Organizer-only: completion status per member, without draft text. */
export async function fetchCycleProgress(
  cycleId: string,
): Promise<CycleProgress[]> {
  const { data, error } = await supabase.rpc("get_cycle_progress", {
    p_cycle_id: cycleId,
  });
  if (error) throw error;
  return data;
}

/** Organizer-only: lets one member revise already-submitted answers. */
export async function reopenSubmission(
  cycleId: string,
  userId: string,
): Promise<void> {
  const { error } = await supabase.rpc("reopen_submission", {
    p_cycle_id: cycleId,
    p_user_id: userId,
  });
  if (error) throw error;
}
