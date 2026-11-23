import { supabase } from "@/lib/supabaseClient";
import { resizeImage } from "@/lib/resizeImage";
import type { IssuePhoto, Profile } from "@/lib/database.types";
import {
  MAX_PHOTO_EDGE,
  PHOTO_BUCKET,
  SIGNED_URL_TTL_SECONDS,
} from "./constants";

export type IssuePhotoWithAuthor = IssuePhoto & {
  author: Pick<Profile, "user_id" | "display_name"> | null;
};

/**
 * Photos the signed-in user may see for a cycle. Row-level security
 * decides which: your own at any time; everyone's once the issue is
 * published (minus any pair an organizer has hidden from each other).
 */
export async function fetchPhotos(
  cycleId: string,
): Promise<IssuePhotoWithAuthor[]> {
  const { data, error } = await supabase
    .from("issue_photos")
    .select("*, author:profiles(user_id, display_name)")
    .eq("cycle_id", cycleId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return data as unknown as IssuePhotoWithAuthor[];
}

/**
 * Time-limited links to the photo files. The bucket is private, so a
 * photo can only be shown through a link that Storage creates for a
 * user it already allows to read that file.
 */
export async function fetchSignedUrls(
  paths: string[],
): Promise<Record<string, string>> {
  if (paths.length === 0) return {};
  const { data, error } = await supabase.storage
    .from(PHOTO_BUCKET)
    .createSignedUrls(paths, SIGNED_URL_TTL_SECONDS);
  if (error) throw error;

  const urls: Record<string, string> = {};
  for (const item of data ?? []) {
    if (item.path && item.signedUrl) urls[item.path] = item.signedUrl;
  }
  return urls;
}

/**
 * Shrinks the photo, uploads the file, then records it. If recording
 * fails the uploaded file is removed again so nothing is left behind.
 */
export async function uploadPhoto(input: {
  cycleId: string;
  authorId: string;
  file: File;
  caption: string;
}): Promise<IssuePhoto> {
  const { blob, width, height } = await resizeImage(input.file, MAX_PHOTO_EDGE);

  const id = crypto.randomUUID();
  // Must equal <cycle_id>/<author_id>/<id>.jpg — the database checks it.
  const storagePath = `${input.cycleId}/${input.authorId}/${id}.jpg`;

  const { error: uploadError } = await supabase.storage
    .from(PHOTO_BUCKET)
    .upload(storagePath, blob, { contentType: "image/jpeg", upsert: false });
  if (uploadError) throw uploadError;

  const { data, error } = await supabase
    .from("issue_photos")
    .insert({
      id,
      cycle_id: input.cycleId,
      author_id: input.authorId,
      storage_path: storagePath,
      caption: input.caption,
      width,
      height,
    })
    .select()
    .single();

  if (error) {
    await supabase.storage.from(PHOTO_BUCKET).remove([storagePath]);
    throw error;
  }
  return data;
}

export async function updatePhotoCaption(
  photoId: string,
  caption: string,
): Promise<IssuePhoto> {
  const { data, error } = await supabase
    .from("issue_photos")
    .update({ caption })
    .eq("id", photoId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

/**
 * Removes the file first, then its row. Order matters: while the row
 * exists the user is still allowed to see (and so delete) the file, and
 * if the second step fails the row can simply be removed again.
 */
export async function deletePhoto(photo: IssuePhoto): Promise<void> {
  const { error: fileError } = await supabase.storage
    .from(PHOTO_BUCKET)
    .remove([photo.storage_path]);
  if (fileError) throw fileError;

  const { error } = await supabase
    .from("issue_photos")
    .delete()
    .eq("id", photo.id);
  if (error) throw error;
}
