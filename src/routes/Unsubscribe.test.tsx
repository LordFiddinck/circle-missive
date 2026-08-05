import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import Unsubscribe from "./Unsubscribe";

const rpcMock = vi.fn().mockResolvedValue({ data: undefined, error: null });

vi.mock("@/lib/supabaseClient", () => ({
  supabase: {
    rpc: (...args: unknown[]) => rpcMock(...args),
  },
}));

function renderWithProviders(path: string) {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false },
      mutations: { retry: false },
    },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route
            path="/unsubscribe/:token/:category"
            element={<Unsubscribe />}
          />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("Unsubscribe", () => {
  beforeEach(() => {
    rpcMock.mockClear();
    rpcMock.mockResolvedValue({ data: undefined, error: null });
  });

  it("calls unsubscribe_by_token and confirms success", async () => {
    renderWithProviders("/unsubscribe/abc123/reminders");

    expect(
      await screen.findByText(/you.re unsubscribed from deadline reminders/i),
    ).toBeInTheDocument();
    expect(rpcMock).toHaveBeenCalledWith("unsubscribe_by_token", {
      p_token: "abc123",
      p_category: "reminders",
    });
  });

  it("shows an error message when the token is invalid", async () => {
    rpcMock.mockResolvedValueOnce({
      data: null,
      error: new Error("This unsubscribe link is no longer valid."),
    });

    renderWithProviders("/unsubscribe/bad-token/announcements");

    expect(
      await screen.findByText(/this unsubscribe link is no longer valid/i),
    ).toBeInTheDocument();
  });

  it("shows a not-recognized message for an unknown category", async () => {
    renderWithProviders("/unsubscribe/abc123/not-a-real-category");

    expect(
      await screen.findByRole("heading", {
        name: /unsubscribe link not recognized/i,
      }),
    ).toBeInTheDocument();
    expect(rpcMock).not.toHaveBeenCalled();
  });
});
