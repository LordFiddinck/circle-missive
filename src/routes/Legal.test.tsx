import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { HashRouter } from "react-router-dom";
import Privacy from "./Privacy";
import Terms from "./Terms";
import Help from "./Help";

// These pages render without any Supabase/session/query dependency —
// they're intentionally reachable while signed out (see App.tsx, where
// they sit outside <ProtectedRoute>), so no mocking is needed here.
describe.each([
  { name: "Privacy", Component: Privacy, heading: /privacy notice/i },
  { name: "Terms", Component: Terms, heading: /terms of use/i },
  { name: "Help", Component: Help, heading: /^help$/i },
])("$name page", ({ Component, heading }) => {
  it("renders its heading and links back to sign-in", async () => {
    render(
      <HashRouter>
        <Component />
      </HashRouter>,
    );

    expect(
      await screen.findByRole("heading", { name: heading, level: 1 }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: /back to sign in/i }),
    ).toHaveAttribute("href", "#/sign-in");
  });

  it("links to the other two legal/help pages via the footer", () => {
    render(
      <HashRouter>
        <Component />
      </HashRouter>,
    );

    const nav = screen.getByRole("navigation", { name: /legal and help/i });
    expect(nav).toBeInTheDocument();
  });
});
