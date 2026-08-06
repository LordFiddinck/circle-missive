import { supabase } from "@/lib/supabaseClient";

export type PendingInvitation = {
  invitationId: string;
  groupId: string;
  groupName: string;
  inviterDisplayName: string;
  expiresAt: string;
};

export async function fetchMyPendingInvitations(): Promise<
  PendingInvitation[]
> {
  const { data, error } = await supabase.rpc("list_my_pending_invitations");
  if (error) throw error;
  return data.map((row) => ({
    invitationId: row.invitation_id,
    groupId: row.group_id,
    groupName: row.group_name,
    inviterDisplayName: row.inviter_display_name,
    expiresAt: row.expires_at,
  }));
}

export async function acceptInvitationById(
  invitationId: string,
): Promise<{ groupId: string }> {
  const { data, error } = await supabase.rpc("accept_invitation_by_id", {
    p_invitation_id: invitationId,
  });
  if (error) throw error;
  return { groupId: data[0].accepted_group_id };
}
