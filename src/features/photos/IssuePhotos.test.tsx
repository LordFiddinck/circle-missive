import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { IssuePhotos } from "./IssuePhotos";

let photos: unknown[] = [];

function makeBuilder() {
  const builder: Record<string, unknown> = {};
  const chain = () => builder;
  builder.select = vi.fn(chain);
  builder.eq = vi.fn(chain);
  builder.order = vi.fn(chain);
  builder.then = (resolve: (value: unknown) => unknown) =>
    Promise.resolve({ data: photos, error: null }).then(resolve);
  return builder;
}

vi.mock("@/lib/supabaseClient", () => ({
  supabase: {
    from: vi.fn(() => makeBuilder()),
    storage: {
      from: vi.fn(() => ({
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

function photo(id: string, caption: string, name: string | null) {
  return {
    id,
    cycle_id: "cycle-1",
    author_id: `user-${id}`,
    storage_path: `cycle-1/user-${id}/${id}.jpg`,
    caption,
    width: 1600,
    height: 1200,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
    author: name ? { user_id: `user-${id}`, display_name: name } : null,
  };
}

function renderPhotos() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <IssuePhotos cycleId="cycle-1" />
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  photos = [];
});

describe("IssuePhotos", () => {
  it("renders nothing when there are no photos to show", async () => {
    const { container } = renderPhotos();
    // Give the query a moment to settle, then confirm nothing appeared.
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(container).toBeEmptyDOMElement();
  });

  it("shows each photo with its description and who took it", async () => {
    photos = [
      photo("a", "Sunrise at the lake", "Maya"),
      photo("b", "", "Tomás"),
    ];
    renderPhotos();

    expect(
      await screen.findByRole("heading", { name: /photos/i }),
    ).toBeInTheDocument();

    const described = await screen.findByAltText("Sunrise at the lake");
    expect(described).toHaveAttribute(
      "src",
      "https://signed.example/cycle-1/user-a/a.jpg",
    );
    expect(screen.getByText("Photo by Maya")).toBeInTheDocument();

    // A photo without a description still gets a meaningful alt text.
    expect(await screen.findByAltText("Photo by Tomás")).toBeInTheDocument();
  });

  it("opens the full-size photo in a new tab without leaking the opener", async () => {
    photos = [photo("a", "Sunrise", "Maya")];
    renderPhotos();

    const link = (await screen.findByAltText("Sunrise")).closest("a");
    expect(link).toHaveAttribute("target", "_blank");
    expect(link).toHaveAttribute("rel", expect.stringContaining("noopener"));
  });
});
