import { supabase } from "@/lib/supabaseClient";
import type { Profile } from "@/lib/database.types";

/** The signed-in user's own profile row. Created automatically by the
 * `handle_new_user` trigger (0001_init_profiles.sql), so this should
 * always resolve — display_name just starts out as ''. */
export async function fetchMyProfile(userId: string): Promise<Profile> {
  const { data, error } = await supabase
    .from("profiles")
    .select("*")
    .eq("user_id", userId)
    .single();
  if (error) throw error;
  return data;
}

export async function updateMyProfile(
  userId: string,
  changes: Partial<Pick<Profile, "display_name">>,
): Promise<Profile> {
  const { data, error } = await supabase
    .from("profiles")
    .update(changes)
    .eq("user_id", userId)
    .select()
    .single();
  if (error) throw error;
  return data;
}
