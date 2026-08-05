import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { HashRouter } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactElement } from "react";
import NewGroup from "./NewGroup";

vi.mock("@/lib/supabaseClient", () => ({
  supabase: {
    rpc: vi.fn().mockResolvedValue({
      data: { id: "group-1", name: "Book Club" },
      error: null,
    }),
  },
}));

function renderWithProviders(ui: ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <HashRouter>{ui}</HashRouter>
    </QueryClientProvider>,
  );
}

describe("NewGroup", () => {
  it("renders a name field and disables submit until a name is entered", async () => {
    renderWithProviders(<NewGroup />);

    expect(
      await screen.findByRole("heading", { name: /start a new group/i }),
    ).toBeInTheDocument();

    const submit = screen.getByRole("button", { name: /create group/i });
    expect(submit).toBeDisabled();

    await userEvent.type(screen.getByLabelText(/group name/i), "Book Club");
    expect(submit).toBeEnabled();
  });
});
