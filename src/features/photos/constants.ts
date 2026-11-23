/** Must match the private Storage bucket created in 0011_issue_photos.sql. */
export const PHOTO_BUCKET = "issue-photos";

/** Must match the limits enforced in the database (0011_issue_photos.sql). */
export const MAX_PHOTOS_PER_MEMBER = 5;
export const MAX_CAPTION_LENGTH = 500;

/** Longest edge, in pixels, that a photo is shrunk to before upload. */
export const MAX_PHOTO_EDGE = 1600;

/** How long a signed link to a photo stays valid, in seconds. */
export const SIGNED_URL_TTL_SECONDS = 3600;
