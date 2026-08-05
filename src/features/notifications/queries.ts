import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchGroupEmailActivity,
  fetchMyEmailPreferences,
  unsubscribeByToken,
  updateMyEmailPreferences,
} from "./api";

export function useMyEmailPreferences(userId: string | undefined) {
  return useQuery({
    queryKey: ["email-preferences", "mine", userId],
    queryFn: () => fetchMyEmailPreferences(userId as string),
    enabled: Boolean(userId),
  });
}

export function useUpdateMyEmailPreferences(userId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (changes: Parameters<typeof updateMyEmailPreferences>[1]) =>
      updateMyEmailPreferences(userId, changes),
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: ["email-preferences", "mine", userId],
      });
    },
  });
}

type UnsubscribeInput = {
  token: string;
  category: "reminders" | "announcements";
};

export function useUnsubscribeByToken() {
  return useMutation({
    mutationFn: ({ token, category }: UnsubscribeInput) =>
      unsubscribeByToken(token, category),
  });
}

export function useGroupEmailActivity(groupId: string | undefined) {
  return useQuery({
    queryKey: ["email-activity", groupId],
    queryFn: () => fetchGroupEmailActivity(groupId as string),
    enabled: Boolean(groupId),
  });
}
