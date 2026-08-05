import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  changeCycleDeadline,
  fetchCurrentCycle,
  fetchCycle,
  fetchCycleProgress,
  fetchCycles,
  publishCycle,
  reopenSubmission,
  skipCycle,
  startCycle,
} from "./api";

export function useCycles(groupId: string | undefined) {
  return useQuery({
    queryKey: ["cycles", groupId],
    queryFn: () => fetchCycles(groupId as string),
    enabled: Boolean(groupId),
  });
}

export function useCurrentCycle(groupId: string | undefined) {
  return useQuery({
    queryKey: ["cycles", "current", groupId],
    queryFn: () => fetchCurrentCycle(groupId as string),
    enabled: Boolean(groupId),
  });
}

export function useCycle(cycleId: string | undefined) {
  return useQuery({
    queryKey: ["cycle", cycleId],
    queryFn: () => fetchCycle(cycleId as string),
    enabled: Boolean(cycleId),
  });
}

function invalidateCycle(
  queryClient: ReturnType<typeof useQueryClient>,
  groupId: string,
  cycleId?: string,
) {
  void queryClient.invalidateQueries({ queryKey: ["cycles", groupId] });
  void queryClient.invalidateQueries({
    queryKey: ["cycles", "current", groupId],
  });
  if (cycleId) {
    void queryClient.invalidateQueries({ queryKey: ["cycle", cycleId] });
  }
}

export function useStartCycle(groupId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => startCycle(groupId),
    onSuccess: () => invalidateCycle(queryClient, groupId),
  });
}

export function useSkipCycle(groupId: string, cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => skipCycle(cycleId),
    onSuccess: () => invalidateCycle(queryClient, groupId, cycleId),
  });
}

export function useChangeCycleDeadline(groupId: string, cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (newDueAt: string) => changeCycleDeadline(cycleId, newDueAt),
    onSuccess: () => invalidateCycle(queryClient, groupId, cycleId),
  });
}

export function usePublishCycle(groupId: string, cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => publishCycle(cycleId),
    onSuccess: () => {
      invalidateCycle(queryClient, groupId, cycleId);
      void queryClient.invalidateQueries({ queryKey: ["issue", cycleId] });
    },
  });
}

export function useCycleProgress(cycleId: string | undefined) {
  return useQuery({
    queryKey: ["cycle-progress", cycleId],
    queryFn: () => fetchCycleProgress(cycleId as string),
    enabled: Boolean(cycleId),
  });
}

export function useReopenSubmission(cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (userId: string) => reopenSubmission(cycleId, userId),
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: ["cycle-progress", cycleId],
      });
    },
  });
}
