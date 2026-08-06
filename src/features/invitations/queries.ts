import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { acceptInvitationById, fetchMyPendingInvitations } from "./api";

export function useMyPendingInvitations(userId: string | undefined) {
  return useQuery({
    queryKey: ["invitations", "mine", userId],
    queryFn: fetchMyPendingInvitations,
    enabled: Boolean(userId),
  });
}

export function useAcceptInvitationById() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: acceptInvitationById,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["invitations", "mine"] });
      void queryClient.invalidateQueries({ queryKey: ["groups"] });
      void queryClient.invalidateQueries({ queryKey: ["memberships", "mine"] });
    },
  });
}
