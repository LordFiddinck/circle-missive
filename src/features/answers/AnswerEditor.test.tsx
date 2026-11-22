import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactElement } from "react";
import { AnswerEditor } from "./AnswerEditor";

type QueryResult = { data: unknown; error: null };

function makeAnswer(
  id: string,
  position: number,
  text: string,
  asker: { user_id: string; display_name: string } | null = null,
) {
  return {
    id: `answer-${id}`,
    question_id: `question-${id}`,
    author_id: "user-1",
    body: "",
    revision: 0,
    submitted_at: null,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
    question: {
      id: `question-${id}`,
      text,
      position,
      asked_by: asker?.user_id ?? null,
      asker,
    },
  };
}

// What the mocked server returns. Tests reassign this; the mock reads it
// lazily on every query, the same way the real client would.
let answers: ReturnType<typeof makeAnswer>[] = [];
// Order of writes as they reach the "server", to assert that pending
// edits are saved *before* a submission is sent.
let callLog: string[] = [];

function makeQueryBuilder(result: QueryResult) {
  const builder: Record<string, unknown> = {};
  const chain = () => builder;
  builder.select = vi.fn(chain);
  builder.eq = vi.fn(chain);
  builder.order = vi.fn(chain);
  builder.update = vi.fn((payload: { body: string }) => {
    callLog.push(`update:${payload.body}`);
    return builder;
  });
  builder.single = vi.fn(() => Promise.resolve(result));
  builder.then = (resolve: (value: QueryResult) => unknown) =>
    Promise.resolve(result).then(resolve);
  return builder;
}

vi.mock("@/lib/supabaseClient", () => ({
  supabase: {
    from: vi.fn(() => makeQueryBuilder({ data: answers, error: null })),
    rpc: vi.fn((name: string) => {
      callLog.push(`rpc:${name}`);
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

beforeEach(() => {
  window.localStorage.clear();
  callLog = [];
  answers = [
    makeAnswer("a", 0, "What made you laugh this week?"),
    makeAnswer("b", 1, "What are you looking forward to?"),
  ];
});

describe("AnswerEditor", () => {
  it("keeps Submit disabled until at least one question has text, live as you type", async () => {
    renderWithProviders(<AnswerEditor groupId="group-1" cycleId="cycle-1" />);

    // The question text legitimately appears twice (the visible <h3>
    // heading and a sr-only <label> for the textarea), so a plain
    // findByText match is ambiguous — scope to the heading role.
    expect(
      await screen.findByRole("heading", {
        name: /what made you laugh this week\?/i,
      }),
    ).toBeInTheDocument();

    const submit = screen.getByRole("button", { name: /submit answers/i });
    expect(submit).toBeDisabled();
    expect(
      screen.getByText(/answer at least one question to submit/i),
    ).toBeInTheDocument();

    const [first] = screen.getAllByRole("textbox");
    await userEvent.type(first, "A very good dog video.");

    // One answer out of two is enough: partial submissions are allowed.
    expect(submit).toBeEnabled();
  });

  it("submits with a question left blank, after confirming and saving pending text", async () => {
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
    renderWithProviders(<AnswerEditor groupId="group-1" cycleId="cycle-1" />);
    await screen.findByRole("heading", { name: /what made you laugh/i });

    const [first] = screen.getAllByRole("textbox");
    await userEvent.type(first, "Dog video");
    // Click Submit straight away — well inside the 800ms autosave delay.
    await userEvent.click(
      screen.getByRole("button", { name: /submit answers/i }),
    );

    expect(confirm).toHaveBeenCalledWith(
      expect.stringMatching(/1 of 2 questions are still blank/i),
    );
    await waitFor(() => expect(callLog).toContain("rpc:submit_answers"));
    // The unsaved text must have been written before the submission, or
    // it would be lost (a submitted answer can't be edited afterwards).
    expect(callLog.indexOf("update:Dog video")).toBeGreaterThanOrEqual(0);
    expect(callLog.indexOf("update:Dog video")).toBeLessThan(
      callLog.indexOf("rpc:submit_answers"),
    );
    confirm.mockRestore();
  });

  it("shows questions in position order even when the server returns them shuffled", async () => {
    // Rows come back in physical order, which changes after every
    // autosave UPDATE. The UI must not depend on it.
    answers = [
      makeAnswer("c", 2, "Third question"),
      makeAnswer("a", 0, "First question"),
      makeAnswer("b", 1, "Second question"),
    ];
    renderWithProviders(<AnswerEditor groupId="group-1" cycleId="cycle-1" />);
    await screen.findByRole("heading", { name: /first question/i });

    const headings = screen
      .getAllByRole("heading", { level: 3 })
      .map((heading) => heading.textContent);
    expect(headings).toEqual([
      "1. First question",
      "2. Second question",
      "3. Third question",
    ]);
  });

  it("credits a question to its asker only when the asker chose to be shown", async () => {
    answers = [
      makeAnswer("a", 0, "Shown question", {
        user_id: "user-2",
        display_name: "Alice",
      }),
      makeAnswer("b", 1, "Anonymous question"),
    ];
    renderWithProviders(<AnswerEditor groupId="group-1" cycleId="cycle-1" />);
    await screen.findByRole("heading", { name: /shown question/i });

    expect(screen.getByText("Asked by Alice")).toBeInTheDocument();
    expect(screen.getAllByText(/^Asked by /)).toHaveLength(1);
  });
});
