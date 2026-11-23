import { usePhotos, usePhotoUrls } from "./queries";

type IssuePhotosProps = {
  cycleId: string;
};

/**
 * The photos section of a published issue. Renders nothing when there
 * are none (or none the viewer is allowed to see).
 */
export function IssuePhotos({ cycleId }: IssuePhotosProps) {
  const photos = usePhotos(cycleId);
  const urls = usePhotoUrls(photos.data);

  if (!photos.data || photos.data.length === 0) return null;

  return (
    <section aria-labelledby="issue-photos-heading">
      <h3 id="issue-photos-heading">Photos</h3>
      <div className="photo-columns">
        {photos.data.map((photo) => {
          const url = urls.data?.[photo.storage_path];
          const name = photo.author?.display_name || "a member";
          return (
            <figure key={photo.id}>
              {url ? (
                <a href={url} target="_blank" rel="noopener noreferrer">
                  <img
                    src={url}
                    width={photo.width}
                    height={photo.height}
                    loading="lazy"
                    alt={photo.caption || `Photo by ${name}`}
                  />
                </a>
              ) : (
                <div
                  className="photo-placeholder"
                  style={{ aspectRatio: `${photo.width} / ${photo.height}` }}
                  aria-hidden="true"
                />
              )}
              <figcaption>
                {photo.caption ? (
                  <span className="photo-caption">{photo.caption}</span>
                ) : null}
                <span className="photo-credit">Photo by {name}</span>
              </figcaption>
            </figure>
          );
        })}
      </div>
    </section>
  );
}
