export type ResizedImage = {
  blob: Blob;
  width: number;
  height: number;
};

/** The browser couldn't read the chosen file as a picture. */
export class UnsupportedImageError extends Error {
  constructor() {
    super(
      "This photo couldn't be read. Try a JPEG or PNG — phone photos in other formats can be exported as JPEG.",
    );
    this.name = "UnsupportedImageError";
  }
}

type Decoded = {
  source: ImageBitmap | HTMLImageElement;
  width: number;
  height: number;
  release: () => void;
};

async function decode(file: File): Promise<Decoded> {
  // Preferred path: asks the browser to apply the camera's rotation
  // (EXIF orientation) so a portrait photo isn't uploaded sideways.
  if (typeof createImageBitmap === "function") {
    try {
      const bitmap = await createImageBitmap(file, {
        imageOrientation: "from-image",
      });
      return {
        source: bitmap,
        width: bitmap.width,
        height: bitmap.height,
        release: () => bitmap.close(),
      };
    } catch {
      // Fall through to the <img> path below.
    }
  }

  // Fallback for browsers without (or with a limited) createImageBitmap.
  // Modern browsers apply EXIF orientation when decoding an <img>.
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    return {
      source: image,
      width: image.naturalWidth,
      height: image.naturalHeight,
      release: () => URL.revokeObjectURL(url),
    };
  } catch {
    URL.revokeObjectURL(url);
    throw new UnsupportedImageError();
  }
}

/**
 * Shrinks a photo so its longest side is at most `maxEdge` pixels and
 * re-encodes it as a JPEG.
 *
 * Re-encoding through a canvas is deliberate, not just a size
 * optimisation: it writes a brand-new file containing only pixels, so
 * metadata such as the GPS location a phone embeds in photos is
 * discarded. Transparent images are flattened onto white.
 */
export async function resizeImage(
  file: File,
  maxEdge = 1600,
  quality = 0.82,
): Promise<ResizedImage> {
  const decoded = await decode(file);

  try {
    if (decoded.width < 1 || decoded.height < 1) {
      throw new UnsupportedImageError();
    }

    const scale = Math.min(
      1,
      maxEdge / Math.max(decoded.width, decoded.height),
    );
    const width = Math.max(1, Math.round(decoded.width * scale));
    const height = Math.max(1, Math.round(decoded.height * scale));

    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    if (!context) throw new UnsupportedImageError();

    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, width, height);
    context.imageSmoothingQuality = "high";
    context.drawImage(decoded.source, 0, 0, width, height);

    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, "image/jpeg", quality),
    );
    if (!blob) throw new UnsupportedImageError();

    return { blob, width, height };
  } finally {
    decoded.release();
  }
}
