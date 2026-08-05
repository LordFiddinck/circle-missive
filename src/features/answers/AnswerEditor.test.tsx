import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactElement } from "react";
import { AnswerEditor } from "./AnswerEditor";

type QueryResult = { data: unknown; error: null };

const answers = [
  {
    id: "answer-1",
    question_id: "question-1",
    author_id: "user-1",
    body: "",
    revision: 0,
    submitted_at: null,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
    question: {
      id: "question-1",
      text: "What made you laugh this week?",
      position: 0,
    },
  },
];

function makeQueryBuilder(result: QueryResult) {
  const builder: Record<string, unknown> = {};
  const chain = () => builder;
  builder.select = vi.fn(chain);
  builder.eq = vi.fn(chain);
  builder.order = vi.fn(chain);
  builder.update = vi.fn(chain);
  builder.single = vi.fn(() => Promise.resolve(result));
  builder.then = (resolve: (value: QueryResult) => unknown) =>
    Promise.resolve(result).then(resolve);
  return builder;
}

vi.mock("@/lib/supabaseClient", () => ({
  supabase: {
    from: vi.fn(() => makeQueryBuilder({ data: answers, error: null })),
    rpc: vi.fn().mockResolvedValue({ data: null, error: null }),
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

describe("AnswerEditor", () => {
  it("keeps Submit disabled until every question has text, live as you type", async () => {
    window.localStorage.clear();

    renderWithProviders(<AnswerEditor groupId="group-1" cycleId="cycle-1" />);

    expect(
      await screen.findByText(/what made you laugh this week\?/i),
    ).toBeInTheDocument();

    const submit = screen.getByRole("button", { name: /submit answers/i });
    expect(submit).toBeDisabled();
    expect(
      screen.getByText(/answer every question before submitting/i),
    ).toBeInTheDocument();

    const textarea = screen.getByRole("textbox");
    await userEvent.type(textarea, "A very good dog video.");

    expect(submit).toBeEnabled();
  });
});
