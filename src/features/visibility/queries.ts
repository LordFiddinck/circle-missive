import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchAnswerBlocks,
  hideAnswersBetween,
  restoreAnswersBetween,
} from "./api";

type Pair = { userOne: string; userTwo: string };

export function useAnswerBlocks(groupId: string) {
  return useQuery({
    queryKey: ["answer-blocks", groupId],
    queryFn: () => fetchAnswerBlocks(groupId),
  });
}

function useRefreshAfterChange(groupId: string) {
  const queryClient = useQueryClient();
  return () => {
    void queryClient.invalidateQueries({
      queryKey: ["answer-blocks", groupId],
    });
    // An organizer can be one of the two people; what they may read in an
    // issue changes the moment the rule does.
    void queryClient.invalidateQueries({ queryKey: ["issue"] });
  };
}

export function useHideAnswers(groupId: string) {
  const refresh = useRefreshAfterChange(groupId);
  return useMutation({
    mutationFn: ({ userOne, userTwo }: Pair) =>
      hideAnswersBetween(groupId, userOne, userTwo),
    onSuccess: refresh,
  });
}

export function useRestoreAnswers(groupId: string) {
  const refresh = useRefreshAfterChange(groupId);
  return useMutation({
    mutationFn: ({ userOne, userTwo }: Pair) =>
      restoreAnswersBetween(groupId, userOne, userTwo),
    onSuccess: refresh,
  });
}
