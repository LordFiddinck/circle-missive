import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactElement } from "react";
import { PhotoUploader } from "./PhotoUploader";
import { UnsupportedImageError } from "@/lib/resizeImage";

type QueryResult = { data: unknown; error: unknown };

function makePhoto(id: string, authorId = "user-1", caption = "") {
  return {
    id,
    cycle_id: "cycle-1",
    author_id: authorId,
    storage_path: `cycle-1/${authorId}/${id}.jpg`,
    caption,
    width: 800,
    height: 600,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
    author: { user_id: authorId, display_name: "Someone" },
  };
}

// What the mocked server holds and how it responds; reset per test.
let photos: ReturnType<typeof makePhoto>[] = [];
let insertError: { message: string } | null = null;
let callLog: string[] = [];
let insertPayloads: Record<string, unknown>[] = [];
let resizeMock = vi.fn();

function makeBuilder(result: (isInsert: boolean) => QueryResult) {
  let isInsert = false;
  const builder: Record<string, unknown> = {};
  const chain = () => builder;
  builder.select = vi.fn(chain);
  builder.eq = vi.fn(chain);
  builder.order = vi.fn(chain);
  builder.insert = vi.fn((payload: Record<string, unknown>) => {
    isInsert = true;
    callLog.push(`insert:${payload.storage_path}`);
    insertPayloads.push(payload);
    return builder;
  });
  builder.update = vi.fn((payload: { caption: string }) => {
    callLog.push(`update:${payload.caption}`);
    return builder;
  });
  builder.delete = vi.fn(() => {
    callLog.push("delete-row");
    return builder;
  });
  builder.single = vi.fn(() => Promise.resolve(result(isInsert)));
  builder.then = (resolve: (value: QueryResult) => unknown) =>
    Promise.resolve(result(isInsert)).then(resolve);
  return builder;
}

vi.mock("@/lib/supabaseClient", () => ({
  supabase: {
    from: vi.fn(() =>
      makeBuilder((isInsert) =>
        isInsert && insertError
          ? { data: null, error: insertError }
          : { data: photos, error: null },
      ),
    ),
    storage: {
      from: vi.fn(() => ({
        upload: vi.fn((path: string, _blob: Blob, options: object) => {
          callLog.push(`upload:${path}:${JSON.stringify(options)}`);
          return Promise.resolve({ data: { path }, error: null });
        }),
        remove: vi.fn((paths: string[]) => {
          callLog.push(`remove-file:${paths.join(",")}`);
          return Promise.resolve({ data: [], error: null });
        }),
        createSignedUrls: vi.fn((paths: string[]) =>
          Promise.resolve({
            data: paths.map((path) => ({
              path,
              signedUrl: `https://signed.example/${path}`,
              error: null,
            })),
            error: null,
          }),
        ),
      })),
    },
  },
}));

vi.mock("@/lib/resizeImage", async (importOriginal) => {
  const original = await importOriginal<typeof import("@/lib/resizeImage")>();
  return {
    ...original,
    resizeImage: (...args: unknown[]) => resizeMock(...args),
  };
});

function renderWithProviders(ui: ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>,
  );
}

function renderUploader() {
  return renderWithProviders(
    <PhotoUploader cycleId="cycle-1" currentUserId="user-1" />,
  );
}

const picture = () =>
  new File(["pixels"], "holiday.png", { type: "image/png" });

beforeEach(() => {
  photos = [];
  insertError = null;
  callLog = [];
  insertPayloads = [];
  resizeMock = vi.fn(() =>
    Promise.resolve({
      blob: new Blob(["jpeg"], { type: "image/jpeg" }),
      width: 1600,
      height: 1200,
    }),
  );
  URL.createObjectURL = vi.fn(() => "blob:preview");
  URL.revokeObjectURL = vi.fn();
  if (!globalThis.crypto?.randomUUID) {
    Object.defineProperty(globalThis, "crypto", {
      value: { randomUUID: () => "00000000-0000-4000-8000-000000000001" },
      configurable: true,
    });
  }
});

describe("PhotoUploader", () => {
  it("keeps Add photo disabled until a picture is chosen, then shows a preview", async () => {
    renderUploader();
    const add = await screen.findByRole("button", { name: /add photo/i });
    expect(add).toBeDisabled();

    await userEvent.upload(screen.getByLabelText(/choose a photo/i), picture());

    expect(add).toBeEnabled();
    expect(screen.getByAltText("Preview")).toHaveAttribute(
      "src",
      "blob:preview",
    );
  });

  it("uploads the shrunken file to the member's own folder, then records it", async () => {
    renderUploader();
    await userEvent.upload(
      await screen.findByLabelText(/choose a photo/i),
      picture(),
    );
    await userEvent.type(
      screen.getByLabelText(/^description$/i),
      "  Sunrise at the lake ",
    );
    await userEvent.click(screen.getByRole("button", { name: /add photo/i }));

    await waitFor(() => expect(insertPayloads).toHaveLength(1));
    const payload = insertPayloads[0];

    // <cycle>/<author>/<photo id>.jpg — what the database requires.
    expect(payload.storage_path).toBe(`cycle-1/user-1/${payload.id}.jpg`);
    expect(payload).toMatchObject({
      cycle_id: "cycle-1",
      author_id: "user-1",
      caption: "Sunrise at the lake",
      width: 1600,
      height: 1200,
    });

    // The file must exist before the row that points at it.
    const upload = callLog.findIndex((entry) => entry.startsWith("upload:"));
    const insert = callLog.findIndex((entry) => entry.startsWith("insert:"));
    expect(upload).toBeGreaterThanOrEqual(0);
    expect(upload).toBeLessThan(insert);
    expect(callLog[upload]).toContain('"contentType":"image/jpeg"');
  });

  it("removes the uploaded file again if recording the photo fails", async () => {
    insertError = { message: "You can add up to 5 photos per issue." };
    renderUploader();
    await userEvent.upload(
      await screen.findByLabelText(/choose a photo/i),
      picture(),
    );
    await userEvent.click(screen.getByRole("button", { name: /add photo/i }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      /up to 5 photos per issue/i,
    );
    const uploaded = callLog
      .find((entry) => entry.startsWith("upload:"))!
      .split(":")[1];
    expect(callLog).toContain(`remove-file:${uploaded}`);
  });

  it("explains when a file can't be read as a picture", async () => {
    resizeMock = vi.fn(() => Promise.reject(new UnsupportedImageError()));
    renderUploader();
    await userEvent.upload(
      await screen.findByLabelText(/choose a photo/i),
      // An image type the browser can't decode (e.g. HEIC in Chrome).
      new File(["x"], "holiday.heic", { type: "image/heic" }),
    );
    await userEvent.click(screen.getByRole("button", { name: /add photo/i }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      /couldn.t be read/i,
    );
    // Nothing was uploaded or recorded.
    expect(callLog).toEqual([]);
  });

  it("lists only my own photos and offers no more once I have five", async () => {
    photos = [
      makePhoto("a", "user-1", "One"),
      makePhoto("b", "user-1", "Two"),
      makePhoto("c", "user-1", "Three"),
      makePhoto("d", "user-1", "Four"),
      makePhoto("e", "user-1", "Five"),
      makePhoto("z", "user-2", "Not mine"),
    ];
    renderUploader();

    const list = await screen.findByRole("list", { name: /your photos/i });
    expect(list.querySelectorAll("li")).toHaveLength(5);
    expect(list).not.toHaveTextContent("Not mine");
    expect(screen.getByText(/maximum of 5 photos/i)).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /add photo/i }),
    ).not.toBeInTheDocument();
  });

  it("saves an edited description", async () => {
    photos = [makePhoto("a", "user-1", "Old words")];
    renderUploader();

    const box = await screen.findByLabelText(/description for photo 1/i);
    const save = screen.getByRole("button", { name: /save description/i });
    expect(save).toBeDisabled();

    await userEvent.clear(box);
    await userEvent.type(box, "New words");
    expect(save).toBeEnabled();
    await userEvent.click(save);

    await waitFor(() => expect(callLog).toContain("update:New words"));
  });

  it("removes the file before its row", async () => {
    photos = [makePhoto("a", "user-1", "Goodbye")];
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
    renderUploader();

    await userEvent.click(
      await screen.findByRole("button", { name: /remove photo/i }),
    );

    await waitFor(() => expect(callLog).toContain("delete-row"));
    expect(callLog.indexOf("remove-file:cycle-1/user-1/a.jpg")).toBeLessThan(
      callLog.indexOf("delete-row"),
    );
    confirm.mockRestore();
  });
});
