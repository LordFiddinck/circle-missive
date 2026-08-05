import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { MembershipRole } from "@/lib/database.types";
import {
  acceptInvitation,
  createGroup,
  createInvitation,
  fetchGroup,
  fetchGroups,
  fetchInvitationPreview,
  fetchInvitations,
  fetchMembers,
  fetchMyMemberships,
  leaveGroup,
  removeMember,
  resendInvitation,
  revokeInvitation,
  setMemberRole,
  updateGroup,
} from "./api";

export function useGroups() {
  return useQuery({ queryKey: ["groups"], queryFn: fetchGroups });
}

export function useMyMemberships(userId: string | undefined) {
  return useQuery({
    queryKey: ["memberships", "mine", userId],
    queryFn: () => fetchMyMemberships(userId as string),
    enabled: Boolean(userId),
  });
}

export function useGroup(groupId: string | undefined) {
  return useQuery({
    queryKey: ["group", groupId],
    queryFn: () => fetchGroup(groupId as string),
    enabled: Boolean(groupId),
  });
}

export function useMembers(groupId: string | undefined) {
  return useQuery({
    queryKey: ["members", groupId],
    queryFn: () => fetchMembers(groupId as string),
    enabled: Boolean(groupId),
  });
}

export function useInvitations(groupId: string | undefined) {
  return useQuery({
    queryKey: ["invitations", groupId],
    queryFn: () => fetchInvitations(groupId as string),
    enabled: Boolean(groupId),
  });
}

export function useCreateGroup() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: createGroup,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["groups"] });
      void queryClient.invalidateQueries({ queryKey: ["memberships", "mine"] });
    },
  });
}

export function useUpdateGroup(groupId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (changes: Parameters<typeof updateGroup>[1]) =>
      updateGroup(groupId, changes),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["group", groupId] });
      void queryClient.invalidateQueries({ queryKey: ["groups"] });
    },
  });
}

export function useCreateInvitation(groupId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (email: string) => createInvitation(groupId, email),
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: ["invitations", groupId],
      });
    },
  });
}

export function useResendInvitation(groupId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: resendInvitation,
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: ["invitations", groupId],
      });
    },
  });
}

export function useRevokeInvitation(groupId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: revokeInvitation,
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: ["invitations", groupId],
      });
    },
  });
}

export function useRemoveMember(groupId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (userId: string) => removeMember(groupId, userId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["members", groupId] });
    },
  });
}

export function useSetMemberRole(groupId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ userId, role }: { userId: string; role: MembershipRole }) =>
      setMemberRole(groupId, userId, role),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["members", groupId] });
    },
  });
}

export function useLeaveGroup() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: leaveGroup,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["groups"] });
      void queryClient.invalidateQueries({ queryKey: ["memberships", "mine"] });
    },
  });
}

export function useInvitationPreview(token: string | undefined) {
  return useQuery({
    queryKey: ["invitation-preview", token],
    queryFn: () => fetchInvitationPreview(token as string),
    enabled: Boolean(token),
    retry: false,
  });
}

export function useAcceptInvitation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: acceptInvitation,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["groups"] });
      void queryClient.invalidateQueries({ queryKey: ["memberships", "mine"] });
    },
  });
}
