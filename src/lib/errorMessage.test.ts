import { describe, expect, it } from "vitest";
import { errorMessage } from "./errorMessage";

describe("errorMessage", () => {
  it("reads the message of a plain database error object", () => {
    // This is the shape the Supabase client returns for a failed query or
    // a `raise exception` in a SQL function — not an Error instance.
    const databaseError = {
      code: "22023",
      details: null,
      hint: null,
      message: "You can add up to 5 photos per issue.",
    };
    expect(databaseError instanceof Error).toBe(false);
    expect(errorMessage(databaseError, "fallback")).toBe(
      "You can add up to 5 photos per issue.",
    );
  });

  it("reads the message of a real Error (auth and storage errors)", () => {
    expect(errorMessage(new Error("Email rate limit exceeded"), "x")).toBe(
      "Email rate limit exceeded",
    );
  });

  it("accepts a bare string", () => {
    expect(errorMessage("Something broke", "x")).toBe("Something broke");
  });

  it("falls back when there is no usable message", () => {
    expect(errorMessage(null, "fallback")).toBe("fallback");
    expect(errorMessage(undefined, "fallback")).toBe("fallback");
    expect(errorMessage({}, "fallback")).toBe("fallback");
    expect(errorMessage({ message: "" }, "fallback")).toBe("fallback");
    expect(errorMessage({ message: 42 }, "fallback")).toBe("fallback");
    expect(errorMessage("   ", "fallback")).toBe("fallback");
  });
});
