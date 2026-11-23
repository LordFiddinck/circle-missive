import { useEffect, useState, type FormEvent } from "react";
import type { IssuePhoto } from "@/lib/database.types";
import { errorMessage } from "@/lib/errorMessage";
import { MAX_CAPTION_LENGTH, MAX_PHOTOS_PER_MEMBER } from "./constants";
import {
  usePhotos,
  usePhotoUrls,
  useDeletePhoto,
  useUpdatePhotoCaption,
  useUploadPhoto,
} from "./queries";

const MAX_FILE_BYTES = 40 * 1024 * 1024;

type PhotoUploaderProps = {
  cycleId: string;
  currentUserId: string;
};

type PhotoRowProps = {
  photo: IssuePhoto;
  index: number;
  url: string | undefined;
  cycleId: string;
};

function PhotoRow({ photo, index, url, cycleId }: PhotoRowProps) {
  const [caption, setCaption] = useState(photo.caption);
  const updateCaption = useUpdatePhotoCaption(cycleId);
  const deletePhoto = useDeletePhoto(cycleId);
  const dirty = caption !== photo.caption;
  const captionId = `photo-caption-${photo.id}`;

  return (
    <li className="photo-item">
      {url ? (
        <img
          className="photo-thumb"
          src={url}
          width={photo.width}
          height={photo.height}
          alt={photo.caption || `Your photo ${index + 1}`}
        />
      ) : (
        <div className="photo-thumb photo-thumb--loading" aria-hidden="true" />
      )}
      <div className="photo-fields">
        <label htmlFor={captionId}>Description for photo {index + 1}</label>
        <textarea
          id={captionId}
          value={caption}
          maxLength={MAX_CAPTION_LENGTH}
          rows={2}
          onChange={(event) => setCaption(event.target.value)}
        />
        <div className="actions">
          <button
            type="button"
            className="quiet"
            disabled={!dirty || updateCaption.isPending}
            onClick={() =>
              updateCaption.mutate({ id: photo.id, caption: caption.trim() })
            }
          >
            {updateCaption.isPending ? "Saving…" : "Save description"}
          </button>
          <button
            type="button"
            className="danger"
            disabled={deletePhoto.isPending}
            onClick={() => {
              if (window.confirm("Remove this photo?")) {
                deletePhoto.mutate(photo);
              }
            }}
          >
            {deletePhoto.isPending ? "Removing…" : "Remove photo"}
          </button>
        </div>
        {updateCaption.isError ? (
          <p role="alert">
            {errorMessage(
              updateCaption.error,
              "Could not save the description.",
            )}
          </p>
        ) : null}
        {deletePhoto.isError ? (
          <p role="alert">
            {errorMessage(deletePhoto.error, "Could not remove this photo.")}
          </p>
        ) : null}
      </div>
    </li>
  );
}

/**
 * While answering is open: add, describe and remove your own photos for
 * this issue. Photos are private to you until the issue is published.
 */
export function PhotoUploader({ cycleId, currentUserId }: PhotoUploaderProps) {
  const photos = usePhotos(cycleId);
  const mine = (photos.data ?? []).filter(
    (photo) => photo.author_id === currentUserId,
  );
  const urls = usePhotoUrls(mine);
  const upload = useUploadPhoto(cycleId, currentUserId);

  const [file, setFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [caption, setCaption] = useState("");
  const [fileError, setFileError] = useState<string | null>(null);
  const [inputKey, setInputKey] = useState(0);

  useEffect(() => {
    if (!file) {
      setPreviewUrl(null);
      return;
    }
    const url = URL.createObjectURL(file);
    setPreviewUrl(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);

  const atLimit = mine.length >= MAX_PHOTOS_PER_MEMBER;

  function handleFileChange(chosen: File | null) {
    setFileError(null);
    if (chosen && chosen.size > MAX_FILE_BYTES) {
      setFile(null);
      setFileError("That file is too large. Choose a photo under 40 MB.");
      return;
    }
    setFile(chosen);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!file) return;
    try {
      await upload.mutateAsync({ file, caption: caption.trim() });
    } catch {
      // The failure is shown below via upload.isError; keep the chosen
      // file and description so the member can simply try again.
      return;
    }
    setFile(null);
    setCaption("");
    setInputKey((key) => key + 1);
  }

  return (
    <section aria-labelledby="photos-heading" className="photos-editor">
      <h2 id="photos-heading">Photos</h2>
      <p>
        Add up to {MAX_PHOTOS_PER_MEMBER} photos to this issue, each with a
        short description. Only you can see them until the issue is published;
        then everyone in your group can.
      </p>

      {photos.isLoading ? <p role="status">Loading your photos…</p> : null}
      {photos.isError ? <p role="alert">Could not load your photos.</p> : null}

      {mine.length > 0 ? (
        <ul aria-label="Your photos" className="photo-list">
          {mine.map((photo, index) => (
            <PhotoRow
              key={photo.id}
              photo={photo}
              index={index}
              cycleId={cycleId}
              url={urls.data?.[photo.storage_path]}
            />
          ))}
        </ul>
      ) : null}

      {atLimit ? (
        <p>
          You&rsquo;ve added the maximum of {MAX_PHOTOS_PER_MEMBER} photos.
          Remove one to add another.
        </p>
      ) : (
        <form onSubmit={handleSubmit} className="photo-add">
          <label htmlFor="photo-file">Choose a photo</label>
          <input
            key={inputKey}
            id="photo-file"
            type="file"
            accept="image/*"
            onChange={(event) =>
              handleFileChange(event.target.files?.[0] ?? null)
            }
          />
          {fileError ? <p role="alert">{fileError}</p> : null}

          {previewUrl ? (
            <img className="photo-preview" src={previewUrl} alt="Preview" />
          ) : null}

          <label htmlFor="photo-caption">Description</label>
          <textarea
            id="photo-caption"
            value={caption}
            maxLength={MAX_CAPTION_LENGTH}
            rows={2}
            onChange={(event) => setCaption(event.target.value)}
          />

          <button
            type="submit"
            className="quiet"
            disabled={!file || upload.isPending}
          >
            {upload.isPending ? "Adding…" : "Add photo"}
          </button>
          {upload.isError ? (
            <p role="alert">
              {errorMessage(upload.error, "Could not add this photo.")}
            </p>
          ) : null}
        </form>
      )}
    </section>
  );
}
