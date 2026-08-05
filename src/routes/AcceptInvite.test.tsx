import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import AcceptInvite from "./AcceptInvite";

vi.mock("@/lib/supabaseClient", () => ({
  supabase: {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: null } }),
      onAuthStateChange: vi.fn().mockReturnValue({
        data: { subscription: { unsubscribe: vi.fn() } },
      }),
      signInWithOtp: vi.fn().mockResolvedValue({ error: null }),
    },
    rpc: vi.fn().mockResolvedValue({
      data: [
        {
          group_name: "Book Club",
          inviter_display_name: "Alice",
          email_normalized: "bob@example.com",
          status: "pending",
          expires_at: new Date(Date.now() + 60_000 * 60 * 24).toISOString(),
        },
      ],
      error: null,
    }),
  },
}));

function renderWithProviders(token: string) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[`/invite/${token}`]}>
        <Routes>
          <Route path="/invite/:token" element={<AcceptInvite />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("AcceptInvite", () => {
  it("shows the invite preview and a sign-in prompt for a signed-out visitor", async () => {
    renderWithProviders("test-token");

    expect(
      await screen.findByRole("heading", {
        name: /you.re invited to book club/i,
      }),
    ).toBeInTheDocument();
    expect(
      screen.getByText("bob@example.com", { selector: "strong" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /send sign-in link/i }),
    ).toBeInTheDocument();
  });
});
