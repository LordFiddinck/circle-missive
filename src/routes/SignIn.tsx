import { useState, type FormEvent } from "react";
import { Navigate } from "react-router-dom";
import { supabase } from "@/lib/supabaseClient";
import { useSession } from "@/lib/useSession";
import { LegalFooter } from "@/components/LegalFooter";

type SubmitState = "idle" | "sending" | "sent" | "error";

export default function SignIn() {
  const { session, loading } = useSession();
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<SubmitState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  if (!loading && session) {
    return <Navigate to="/" replace />;
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setStatus("sending");
    setErrorMessage(null);

    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim().toLowerCase(),
      options: {
        emailRedirectTo: window.location.origin + window.location.pathname,
      },
    });

    if (error) {
      setStatus("error");
      setErrorMessage(error.message);
      return;
    }

    setStatus("sent");
  }

  return (
    <main>
      <h1>Sign in to Circle Missive</h1>
      <p>
        Enter the email address you were invited with. We&rsquo;ll send you a
        one-time sign-in link — no password needed.
      </p>

      {status === "sent" ? (
        <p role="status" aria-live="polite">
          Check your inbox for a sign-in link. You can close this tab.
        </p>
      ) : (
        <form onSubmit={handleSubmit}>
          <label htmlFor="email">Email address</label>
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
          <button type="submit" disabled={status === "sending"}>
            {status === "sending" ? "Sending link…" : "Send sign-in link"}
          </button>
        </form>
      )}

      {status === "error" && errorMessage ? (
        <p role="alert">Could not send the link: {errorMessage}</p>
      ) : null}

      <LegalFooter />
    </main>
  );
}
