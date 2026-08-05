import { supabase } from "@/lib/supabaseClient";
import type {
  EmailActivitySummary,
  EmailPreferences,
} from "@/lib/database.types";

/** The signed-in user's own email preferences (created automatically
 * alongside their profile). */
export async function fetchMyEmailPreferences(
  userId: string,
): Promise<EmailPreferences> {
  const { data, error } = await supabase
    .from("email_preferences")
    .select("*")
    .eq("user_id", userId)
    .single();
  if (error) throw error;
  return data;
}

export async function updateMyEmailPreferences(
  userId: string,
  changes: Partial<
    Pick<EmailPreferences, "reminders_enabled" | "announcements_enabled">
  >,
): Promise<EmailPreferences> {
  const { data, error } = await supabase
    .from("email_preferences")
    .update(changes)
    .eq("user_id", userId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Callable while signed out — the whole point of a one-click unsubscribe
 * link. */
export async function unsubscribeByToken(
  token: string,
  category: "reminders" | "announcements",
): Promise<void> {
  const { error } = await supabase.rpc("unsubscribe_by_token", {
    p_token: token,
    p_category: category,
  });
  if (error) throw error;
}

/** Organizer-only: a per-template/status summary of a group's outgoing mail. */
export async function fetchGroupEmailActivity(
  groupId: string,
): Promise<EmailActivitySummary[]> {
  const { data, error } = await supabase.rpc("get_group_email_activity", {
    p_group_id: groupId,
  });
  if (error) throw error;
  return data;
}
