import { supabase } from "@/lib/supabaseClient";
import type {
  Group,
  Invitation,
  Membership,
  MembershipRole,
  Profile,
} from "@/lib/database.types";

export type MemberWithProfile = Membership & {
  profile: Pick<Profile, "user_id" | "display_name"> | null;
};

/** All the groups the signed-in user currently belongs to. */
export async function fetchGroups(): Promise<Group[]> {
  const { data, error } = await supabase
    .from("groups")
    .select("*")
    .order("name", { ascending: true });
  if (error) throw error;
  return data;
}

/** The signed-in user's own membership rows, used to show their role per group. */
export async function fetchMyMemberships(
  userId: string,
): Promise<Membership[]> {
  const { data, error } = await supabase
    .from("memberships")
    .select("*")
    .eq("user_id", userId)
    .eq("status", "active");
  if (error) throw error;
  return data;
}

export async function fetchGroup(groupId: string): Promise<Group> {
  const { data, error } = await supabase
    .from("groups")
    .select("*")
    .eq("id", groupId)
    .single();
  if (error) throw error;
  return data;
}

/** Active members of a group, joined with their display name. */
export async function fetchMembers(
  groupId: string,
): Promise<MemberWithProfile[]> {
  const { data, error } = await supabase
    .from("memberships")
    .select(
      "*, profile:profiles!memberships_user_id_fkey(user_id, display_name)",
    )
    .eq("group_id", groupId)
    .eq("status", "active")
    .order("joined_at", { ascending: true });
  if (error) throw error;
  return data as unknown as MemberWithProfile[];
}

/** An organizer's view of every invitation ever sent for a group. */
export async function fetchInvitations(groupId: string): Promise<Invitation[]> {
  const { data, error } = await supabase
    .from("invitations")
    .select("*")
    .eq("group_id", groupId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data;
}

export async function createGroup(input: {
  name: string;
  timezone: string;
  intervalDays: number;
  questionPhaseDays: number;
  answerPhaseDays: number;
}): Promise<Group> {
  const { data, error } = await supabase.rpc("create_group", {
    p_name: input.name,
    p_timezone: input.timezone,
    p_interval_days: input.intervalDays,
    p_question_phase_days: input.questionPhaseDays,
    p_answer_phase_days: input.answerPhaseDays,
  });
  if (error) throw error;
  return data;
}

export async function updateGroup(
  groupId: string,
  changes: Partial<
    Pick<
      Group,
      | "name"
      | "timezone"
      | "interval_days"
      | "question_phase_days"
      | "answer_phase_days"
    >
  >,
): Promise<Group> {
  const { data, error } = await supabase
    .from("groups")
    .update(changes)
    .eq("id", groupId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Returns the raw invite token once — the caller must show/copy it now, it can't be re-fetched later. */
export async function createInvitation(
  groupId: string,
  email: string,
): Promise<{ invitationId: string; token: string; expiresAt: string }> {
  const { data, error } = await supabase.rpc("create_invitation", {
    p_group_id: groupId,
    p_email: email,
  });
  if (error) throw error;
  const row = data[0];
  return {
    invitationId: row.invitation_id,
    token: row.token,
    expiresAt: row.expires_at,
  };
}

export async function resendInvitation(
  invitationId: string,
): Promise<{ token: string; expiresAt: string }> {
  const { data, error } = await supabase.rpc("resend_invitation", {
    p_invitation_id: invitationId,
  });
  if (error) throw error;
  const row = data[0];
  return { token: row.token, expiresAt: row.expires_at };
}

export async function revokeInvitation(invitationId: string): Promise<void> {
  const { error } = await supabase.rpc("revoke_invitation", {
    p_invitation_id: invitationId,
  });
  if (error) throw error;
}

export async function removeMember(
  groupId: string,
  userId: string,
): Promise<void> {
  const { error } = await supabase.rpc("remove_member", {
    p_group_id: groupId,
    p_user_id: userId,
  });
  if (error) throw error;
}

export async function setMemberRole(
  groupId: string,
  userId: string,
  role: MembershipRole,
): Promise<void> {
  const { error } = await supabase.rpc("set_member_role", {
    p_group_id: groupId,
    p_user_id: userId,
    p_role: role,
  });
  if (error) throw error;
}

export async function leaveGroup(groupId: string): Promise<void> {
  const { error } = await supabase.rpc("leave_group", { p_group_id: groupId });
  if (error) throw error;
}

/** Invite links carry the raw token in the URL fragment (e.g. #/invite/<token>). */
export type InvitationPreview = {
  groupName: string;
  inviterDisplayName: string;
  emailNormalized: string;
  status: Invitation["status"];
  expiresAt: string;
};

export async function fetchInvitationPreview(
  token: string,
): Promise<InvitationPreview | null> {
  const { data, error } = await supabase.rpc("get_invitation_preview", {
    p_token: token,
  });
  if (error) throw error;
  const row = data[0];
  if (!row) return null;
  return {
    groupName: row.group_name,
    inviterDisplayName: row.inviter_display_name,
    emailNormalized: row.email_normalized,
    status: row.status,
    expiresAt: row.expires_at,
  };
}

export async function acceptInvitation(
  token: string,
): Promise<{ groupId: string }> {
  const { data, error } = await supabase.rpc("accept_invitation", {
    p_token: token,
  });
  if (error) throw error;
  return { groupId: data[0].accepted_group_id };
}
