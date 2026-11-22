import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { AnswerVisibility } from "./AnswerVisibility";

type QueryResult = { data: unknown; error: null };

function member(userId: string, name: string) {
  return {
    id: `membership-${userId}`,
    group_id: "group-1",
    user_id: userId,
    role: "member",
    status: "active",
    invited_by: null,
    joined_at: "2026-01-01T00:00:00.000Z",
    left_at: null,
    profile: { user_id: userId, display_name: name },
  };
}

// Ids are compared as strings, like the database's canonical user_a < user_b.
const ALICE = "user-a";
const BOB = "user-b";
const CAROL = "user-c";
const GONE = "user-z";

let members = [
  member(ALICE, "Alice"),
  member(BOB, "Bob"),
  member(CAROL, "Carol"),
];
let blocks: {
  id: string;
  group_id: string;
  user_a: string;
  user_b: string;
  created_by: string | null;
  created_at: string;
}[] = [];
let rpcCalls: { name: string; args: unknown }[] = [];

function makeQueryBuilder(result: QueryResult) {
  const builder: Record<string, unknown> = {};
  const chain = () => builder;
  builder.select = vi.fn(chain);
  builder.eq = vi.fn(chain);
  builder.order = vi.fn(chain);
  builder.then = (resolve: (value: QueryResult) => unknown) =>
    Promise.resolve(result).then(resolve);
  return builder;
}

vi.mock("@/lib/supabaseClient", () => ({
  supabase: {
    from: vi.fn((table: string) =>
      makeQueryBuilder({
        data: table === "answer_visibility_blocks" ? blocks : members,
        error: null,
      }),
    ),
    rpc: vi.fn((name: string, args: unknown) => {
      rpcCalls.push({ name, args });
      return Promise.resolve({ data: null, error: null });
    }),
  },
}));

function renderComponent() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <AnswerVisibility groupId="group-1" />
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  members = [
    member(ALICE, "Alice"),
    member(BOB, "Bob"),
    member(CAROL, "Carol"),
  ];
  blocks = [];
  rpcCalls = [];
});

describe("AnswerVisibility", () => {
  it("explains the rule, and says when nobody is hidden", async () => {
    renderComponent();
    expect(
      await screen.findByText(/no one is hidden from anyone right now/i),
    ).toBeInTheDocument();
    expect(screen.getByText(/they won.t be told/i)).toBeInTheDocument();
  });

  it("keeps the button disabled until two different people are chosen", async () => {
    renderComponent();
    const first = await screen.findByLabelText(/first person/i);
    const second = screen.getByLabelText(/second person/i);
    const button = screen.getByRole("button", {
      name: /hide their answers from each other/i,
    });
    expect(button).toBeDisabled();

    await userEvent.selectOptions(first, BOB);
    expect(button).toBeDisabled();

    await userEvent.selectOptions(second, CAROL);
    expect(button).toBeEnabled();

    // The same person can't be picked on both sides.
    expect(within(second).getByRole("option", { name: "Bob" })).toBeDisabled();
  });

  it("hides the chosen pair through the database function", async () => {
    renderComponent();
    await userEvent.selectOptions(
      await screen.findByLabelText(/first person/i),
      BOB,
    );
    await userEvent.selectOptions(
      screen.getByLabelText(/second person/i),
      CAROL,
    );
    await userEvent.click(
      screen.getByRole("button", {
        name: /hide their answers from each other/i,
      }),
    );

    await waitFor(() =>
      expect(rpcCalls).toEqual([
        {
          name: "hide_answers_between",
          args: { p_group_id: "group-1", p_user_one: BOB, p_user_two: CAROL },
        },
      ]),
    );
  });

  it("lists hidden pairs by name, including someone who has left", async () => {
    blocks = [
      {
        id: "block-1",
        group_id: "group-1",
        user_a: ALICE,
        user_b: BOB,
        created_by: ALICE,
        created_at: "2026-01-01T00:00:00.000Z",
      },
      {
        id: "block-2",
        group_id: "group-1",
        user_a: CAROL,
        user_b: GONE,
        created_by: ALICE,
        created_at: "2026-01-02T00:00:00.000Z",
      },
    ];
    renderComponent();

    const list = await screen.findByRole("list", { name: /hidden pairs/i });
    expect(list).toHaveTextContent("Alice and Bob");
    expect(list).toHaveTextContent("Carol and A former member");
  });

  it("refuses to add a pair that is already hidden, in either order", async () => {
    blocks = [
      {
        id: "block-1",
        group_id: "group-1",
        user_a: ALICE,
        user_b: BOB,
        created_by: ALICE,
        created_at: "2026-01-01T00:00:00.000Z",
      },
    ];
    renderComponent();
    await userEvent.selectOptions(
      await screen.findByLabelText(/first person/i),
      BOB,
    );
    await userEvent.selectOptions(
      screen.getByLabelText(/second person/i),
      ALICE,
    );

    expect(
      screen.getByText(/already hidden from each other/i),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", {
        name: /hide their answers from each other/i,
      }),
    ).toBeDisabled();
  });

  it("lets an organizer allow a pair again after confirming", async () => {
    blocks = [
      {
        id: "block-1",
        group_id: "group-1",
        user_a: ALICE,
        user_b: BOB,
        created_by: ALICE,
        created_at: "2026-01-01T00:00:00.000Z",
      },
    ];
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
    renderComponent();

    await userEvent.click(
      await screen.findByRole("button", { name: /allow again/i }),
    );

    expect(confirm).toHaveBeenCalledWith(
      expect.stringMatching(/Alice and Bob see each other's answers again/),
    );
    await waitFor(() =>
      expect(rpcCalls).toEqual([
        {
          name: "restore_answers_between",
          args: { p_group_id: "group-1", p_user_one: ALICE, p_user_two: BOB },
        },
      ]),
    );
    confirm.mockRestore();
  });
});
