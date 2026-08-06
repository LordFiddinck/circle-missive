import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { fetchMyProfile, updateMyProfile } from "./api";

export function useMyProfile(userId: string | undefined) {
  return useQuery({
    queryKey: ["profile", "mine", userId],
    queryFn: () => fetchMyProfile(userId as string),
    enabled: Boolean(userId),
  });
}

export function useUpdateMyProfile(userId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (changes: Parameters<typeof updateMyProfile>[1]) =>
      updateMyProfile(userId, changes),
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: ["profile", "mine", userId],
      });
      // Other screens (MemberList, OrganizerProgress, etc.) embed
      // this user's display_name under their own query keys — bust
      // broadly so a renamed member shows up immediately everywhere,
      // not just on this page.
      void queryClient.invalidateQueries({ queryKey: ["members"] });
      void queryClient.invalidateQueries({ queryKey: ["memberships"] });
    },
  });
}
