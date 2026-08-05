import { useEffect, useRef } from "react";
import { Link, useParams } from "react-router-dom";
import { useUnsubscribeByToken } from "@/features/notifications/queries";

type EmailCategory = "reminders" | "announcements";

const CATEGORY_LABEL: Record<EmailCategory, string> = {
  reminders: "deadline reminders",
  announcements: "announcements",
};

function isEmailCategory(value: string | undefined): value is EmailCategory {
  return value === "reminders" || value === "announcements";
}

export default function Unsubscribe() {
  const { token, category: rawCategory } = useParams<{
    token: string;
    category: string;
  }>();
  const category = isEmailCategory(rawCategory) ? rawCategory : undefined;
  const unsubscribe = useUnsubscribeByToken();
  const attempted = useRef(false);

  useEffect(() => {
    if (attempted.current || !token || !category) return;
    attempted.current = true;
    unsubscribe.mutate({ token, category });
    // eslint-disable-next-line react-hooks/exhaustive-deps -- run once per pair
  }, [token, category]);

  if (!token || !category) {
    return (
      <main>
        <h1>Unsubscribe link not recognized</h1>
        <p>This link is missing information it needs to work.</p>
      </main>
    );
  }

  return (
    <main>
      <h1>Unsubscribe</h1>

      {unsubscribe.isPending ? (
        <p role="status" aria-live="polite">
          Updating your email preferences…
        </p>
      ) : null}

      {unsubscribe.isSuccess ? (
        <p role="status" aria-live="polite">
          You&rsquo;re unsubscribed from {CATEGORY_LABEL[category]}. You can
          change this and other email preferences any time from your account
          page.
        </p>
      ) : null}

      {unsubscribe.isError ? (
        <p role="alert">
          {unsubscribe.error instanceof Error
            ? unsubscribe.error.message
            : "This unsubscribe link is no longer valid."}
        </p>
      ) : null}

      <p>
        <Link to="/sign-in">Sign in</Link> to manage all of your email
        preferences.
      </p>
    </main>
  );
}
