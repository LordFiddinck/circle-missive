import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchMyAnswers,
  saveAnswerDraft,
  submitAnswers,
  submitLateAnswer,
} from "./api";

export function useMyAnswers(cycleId: string | undefined) {
  return useQuery({
    queryKey: ["my-answers", cycleId],
    queryFn: () => fetchMyAnswers(cycleId as string),
    enabled: Boolean(cycleId),
  });
}

export function useSaveAnswerDraft(cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ answerId, body }: { answerId: string; body: string }) =>
      saveAnswerDraft(answerId, body),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["my-answers", cycleId] });
    },
  });
}

export function useSubmitAnswers(groupId: string, cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => submitAnswers(cycleId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["my-answers", cycleId] });
      void queryClient.invalidateQueries({
        queryKey: ["cycle-progress", cycleId],
      });
      void queryClient.invalidateQueries({ queryKey: ["cycles", groupId] });
    },
  });
}

export function useSubmitLateAnswer(cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ questionId, body }: { questionId: string; body: string }) =>
      submitLateAnswer(questionId, body),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["issue", cycleId] });
      void queryClient.invalidateQueries({ queryKey: ["my-answers", cycleId] });
    },
  });
}
