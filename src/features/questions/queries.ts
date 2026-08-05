import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  createProposal,
  deleteProposal,
  fetchCycleQuestions,
  fetchProposals,
  finalizeQuestions,
  updateProposal,
} from "./api";

export function useProposals(cycleId: string | undefined) {
  return useQuery({
    queryKey: ["proposals", cycleId],
    queryFn: () => fetchProposals(cycleId as string),
    enabled: Boolean(cycleId),
  });
}

export function useCycleQuestions(cycleId: string | undefined) {
  return useQuery({
    queryKey: ["cycle-questions", cycleId],
    queryFn: () => fetchCycleQuestions(cycleId as string),
    enabled: Boolean(cycleId),
  });
}

export function useCreateProposal(cycleId: string, authorId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (text: string) => createProposal(cycleId, authorId, text),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["proposals", cycleId] });
    },
  });
}

export function useUpdateProposal(cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, text }: { id: string; text: string }) =>
      updateProposal(id, text),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["proposals", cycleId] });
    },
  });
}

export function useDeleteProposal(cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: deleteProposal,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["proposals", cycleId] });
    },
  });
}

export function useFinalizeQuestions(groupId: string, cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (orderedProposalIds: string[]) =>
      finalizeQuestions(cycleId, orderedProposalIds),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["proposals", cycleId] });
      void queryClient.invalidateQueries({
        queryKey: ["cycle-questions", cycleId],
      });
      void queryClient.invalidateQueries({ queryKey: ["cycle", cycleId] });
      void queryClient.invalidateQueries({ queryKey: ["cycles", groupId] });
      void queryClient.invalidateQueries({
        queryKey: ["cycles", "current", groupId],
      });
    },
  });
}
