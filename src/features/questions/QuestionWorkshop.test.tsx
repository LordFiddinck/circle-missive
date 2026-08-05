import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactElement } from "react";
import { QuestionWorkshop } from "./QuestionWorkshop";

type QueryResult = { data: unknown; error: null };

function makeQueryBuilder(result: QueryResult) {
  const builder: Record<string, unknown> = {};
  const chain = () => builder;
  builder.select = vi.fn(chain);
  builder.eq = vi.fn(chain);
  builder.order = vi.fn(chain);
  builder.insert = vi.fn(chain);
  builder.update = vi.fn(chain);
  builder.delete = vi.fn(chain);
  builder.single = vi.fn(() => Promise.resolve(result));
  builder.then = (resolve: (value: QueryResult) => unknown) =>
    Promise.resolve(result).then(resolve);
  return builder;
}

vi.mock("@/lib/supabaseClient", () => ({
  supabase: {
    from: vi.fn(() => makeQueryBuilder({ data: [], error: null })),
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

describe("QuestionWorkshop", () => {
  it("lets a member type a new question suggestion and enables submit", async () => {
    renderWithProviders(
      <QuestionWorkshop
        groupId="group-1"
        cycleId="cycle-1"
        currentUserId="user-1"
        isOrganizer={false}
      />,
    );

    expect(
      await screen.findByText(/no one has suggested a question yet/i),
    ).toBeInTheDocument();

    const input = screen.getByLabelText(/suggest a question/i);
    const submit = screen.getByRole("button", { name: /add suggestion/i });
    expect(submit).toBeDisabled();

    await userEvent.type(input, "What's your favorite season?");
    expect(submit).toBeEnabled();
  });

  it("does not show organizer finalize controls to a plain member", async () => {
    renderWithProviders(
      <QuestionWorkshop
        groupId="group-1"
        cycleId="cycle-1"
        currentUserId="user-1"
        isOrganizer={false}
      />,
    );

    await screen.findByText(/no one has suggested a question yet/i);
    expect(
      screen.queryByRole("heading", { name: /final questions for this cycle/i }),
    ).not.toBeInTheDocument();
  });
});
