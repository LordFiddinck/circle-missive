import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactElement } from "react";
import { QuestionWorkshop } from "./QuestionWorkshop";

type QueryResult = { data: unknown; error: null };

function makeProposal(
  id: string,
  text: string,
  authorId: string,
  authorName: string,
  showAuthor: boolean,
) {
  return {
    id,
    cycle_id: "cycle-1",
    author_id: authorId,
    text,
    show_author: showAuthor,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
    author: { user_id: authorId, display_name: authorName },
  };
}

// What the mocked server returns for any table query; reassigned per test.
let proposals: ReturnType<typeof makeProposal>[] = [];
let insertPayloads: Record<string, unknown>[] = [];
let rpcCalls: { name: string; args: unknown }[] = [];

function makeQueryBuilder(result: QueryResult) {
  const builder: Record<string, unknown> = {};
  const chain = () => builder;
  builder.select = vi.fn(chain);
  builder.eq = vi.fn(chain);
  builder.order = vi.fn(chain);
  builder.insert = vi.fn((payload: Record<string, unknown>) => {
    insertPayloads.push(payload);
    return builder;
  });
  builder.update = vi.fn(chain);
  builder.delete = vi.fn(chain);
  builder.single = vi.fn(() => Promise.resolve(result));
  builder.then = (resolve: (value: QueryResult) => unknown) =>
    Promise.resolve(result).then(resolve);
  return builder;
}

vi.mock("@/lib/supabaseClient", () => ({
  supabase: {
    from: vi.fn(() => makeQueryBuilder({ data: proposals, error: null })),
    rpc: vi.fn((name: string, args: unknown) => {
      rpcCalls.push({ name, args });
      return Promise.resolve({ data: null, error: null });
    }),
  },
}));

function renderWithProviders(ui: ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>,
  );
}

function renderWorkshop(isOrganizer: boolean) {
  return renderWithProviders(
    <QuestionWorkshop
      groupId="group-1"
      cycleId="cycle-1"
      currentUserId="user-1"
      isOrganizer={isOrganizer}
    />,
  );
}

beforeEach(() => {
  proposals = [];
  insertPayloads = [];
  rpcCalls = [];
});

describe("QuestionWorkshop", () => {
  it("lets a member type a new question suggestion and enables submit", async () => {
    renderWorkshop(false);

    expect(
      await screen.findByText(/no one has suggested a question yet/i),
    ).toBeInTheDocument();

    const input = screen.getByLabelText(/suggest a question/i);
    const submit = screen.getByRole("button", { name: /add suggestion/i });
    expect(submit).toBeDisabled();

    await userEvent.type(input, "What's your favorite season?");
    expect(submit).toBeEnabled();
  });

  it("does not show organizer finalize or release controls to a plain member", async () => {
    renderWorkshop(false);

    await screen.findByText(/no one has suggested a question yet/i);
    expect(
      screen.queryByRole("heading", {
        name: /final questions for this cycle/i,
      }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /release all/i }),
    ).not.toBeInTheDocument();
  });

  it("shows my name on a new suggestion by default, and lets me opt out", async () => {
    renderWorkshop(false);
    await screen.findByText(/no one has suggested a question yet/i);

    const showName = screen.getByLabelText(/show my name on this question/i);
    expect(showName).toBeChecked();

    await userEvent.type(
      screen.getByLabelText(/suggest a question/i),
      "A quiet one",
    );
    await userEvent.click(showName);
    expect(showName).not.toBeChecked();
    await userEvent.click(
      screen.getByRole("button", { name: /add suggestion/i }),
    );

    await waitFor(() => expect(insertPayloads).toHaveLength(1));
    expect(insertPayloads[0]).toMatchObject({
      text: "A quiet one",
      author_id: "user-1",
      show_author: false,
    });
  });

  it("credits suggestions to their authors only when they chose to be shown", async () => {
    proposals = [
      makeProposal("p1", "Named question", "user-2", "Alice", true),
      makeProposal("p2", "Hidden question", "user-3", "Bob", false),
      makeProposal("p3", "My own hidden one", "user-1", "Me", false),
    ];
    renderWorkshop(false);

    const list = await screen.findByRole("list", {
      name: /suggested questions/i,
    });
    const rowFor = (title: string) =>
      within(list).getByText(title).closest("li") as HTMLElement;

    expect(rowFor("Named question")).toHaveTextContent("Alice");
    // Others' hidden names are never rendered, only "Anonymous".
    expect(rowFor("Hidden question")).toHaveTextContent("Anonymous");
    expect(list).not.toHaveTextContent("Bob");
    // The author can still see that their own name is hidden.
    expect(rowFor("My own hidden one")).toHaveTextContent(
      "you — name hidden from others",
    );
  });

  it("lets the organizer release every suggestion in one step", async () => {
    proposals = [
      makeProposal("p1", "First", "user-2", "Alice", true),
      makeProposal("p2", "Second", "user-3", "Bob", true),
    ];
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
    renderWorkshop(true);

    await userEvent.click(
      await screen.findByRole("button", {
        name: /release all 2 suggestions now/i,
      }),
    );

    expect(confirm).toHaveBeenCalledWith(
      expect.stringMatching(/release all 2 suggested questions now/i),
    );
    await waitFor(() =>
      expect(rpcCalls).toEqual([
        { name: "release_questions", args: { p_cycle_id: "cycle-1" } },
      ]),
    );
    confirm.mockRestore();
  });

  it("disables release when nothing has been suggested", async () => {
    renderWorkshop(true);
    await screen.findByText(/no one has suggested a question yet/i);
    expect(screen.getByRole("button", { name: /release all/i })).toBeDisabled();
  });
});
