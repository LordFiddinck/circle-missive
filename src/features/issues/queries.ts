import { useQuery } from "@tanstack/react-query";
import { fetchIssueEntries } from "./api";

export function useIssueEntries(cycleId: string | undefined) {
  return useQuery({
    queryKey: ["issue", cycleId],
    queryFn: () => fetchIssueEntries(cycleId as string),
    enabled: Boolean(cycleId),
  });
}
