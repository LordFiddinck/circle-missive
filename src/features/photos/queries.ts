import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  deletePhoto,
  fetchPhotos,
  fetchSignedUrls,
  updatePhotoCaption,
  uploadPhoto,
} from "./api";
import type { IssuePhoto } from "@/lib/database.types";
import { SIGNED_URL_TTL_SECONDS } from "./constants";

export function usePhotos(cycleId: string) {
  return useQuery({
    queryKey: ["photos", cycleId],
    queryFn: () => fetchPhotos(cycleId),
  });
}

/**
 * Signed links for a set of photos. They expire after an hour, so the
 * cache is treated as stale well before then and refetched.
 */
export function usePhotoUrls(photos: IssuePhoto[] | undefined) {
  const paths = (photos ?? []).map((photo) => photo.storage_path).sort();
  return useQuery({
    queryKey: ["photo-urls", paths],
    queryFn: () => fetchSignedUrls(paths),
    enabled: paths.length > 0,
    staleTime: (SIGNED_URL_TTL_SECONDS * 1000) / 2,
  });
}

export function useUploadPhoto(cycleId: string, authorId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ file, caption }: { file: File; caption: string }) =>
      uploadPhoto({ cycleId, authorId, file, caption }),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["photos", cycleId] }),
  });
}

export function useUpdatePhotoCaption(cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, caption }: { id: string; caption: string }) =>
      updatePhotoCaption(id, caption),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["photos", cycleId] }),
  });
}

export function useDeletePhoto(cycleId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (photo: IssuePhoto) => deletePhoto(photo),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["photos", cycleId] }),
  });
}
