import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { HashRouter } from "react-router-dom";
import SignIn from "./SignIn";

// The real Supabase client requires env vars that aren't set in the test
// environment, and we don't want tests hitting a network. Mock it instead.
vi.mock("@/lib/supabaseClient", () => ({
  supabase: {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: null } }),
      onAuthStateChange: vi.fn().mockReturnValue({
        data: { subscription: { unsubscribe: vi.fn() } },
      }),
      signInWithOtp: vi.fn().mockResolvedValue({ error: null }),
    },
  },
}));

describe("SignIn", () => {
  it("renders an email field and submit button", async () => {
    render(
      <HashRouter>
        <SignIn />
      </HashRouter>,
    );

    expect(
      await screen.findByRole("heading", {
        name: /sign in to circle missive/i,
      }),
    ).toBeInTheDocument();
    expect(screen.getByLabelText(/email address/i)).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /send sign-in link/i }),
    ).toBeInTheDocument();
  });

  it("links to the privacy notice and terms before sign-in", async () => {
    render(
      <HashRouter>
        <SignIn />
      </HashRouter>,
    );

    expect(
      await screen.findByRole("link", { name: /privacy/i }),
    ).toHaveAttribute("href", "#/privacy");
    expect(screen.getByRole("link", { name: /terms/i })).toHaveAttribute(
      "href",
      "#/terms",
    );
  });
});
