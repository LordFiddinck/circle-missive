// Thin wrapper around the Resend API. Never called from the browser —
// only from email-worker, using a project secret. See the Resend +
// Supabase guide linked in implementation_plan.md Section 15.
const RESEND_API_URL = "https://api.resend.com/emails";

export type SendEmailInput = {
  to: string;
  subject: string;
  html: string;
  text: string;
};

export type SendEmailResult = { providerMessageId: string };

export async function sendViaResend(input: SendEmailInput): Promise<SendEmailResult> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  // e.g. "Circle Missive <notifications@mail.example.org>" — the
  // mailbox must be on a domain you've verified with Resend (SPF/
  // DKIM/DMARC), per Section 6 of the implementation plan.
  const fromAddress = Deno.env.get("RESEND_FROM_ADDRESS");

  if (!apiKey || !fromAddress) {
    throw new Error(
      "RESEND_API_KEY and RESEND_FROM_ADDRESS must be set as Supabase project secrets.",
    );
  }

  const response = await fetch(RESEND_API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromAddress,
      to: input.to,
      subject: input.subject,
      html: input.html,
      text: input.text,
    }),
  });

  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    // Thrown errors propagate to the caller (email-worker), which
    // treats them as a transient failure and retries with backoff —
    // see mark_outbox_failed() in 0004_scheduling_email.sql. A
    // permanently invalid request (e.g. a malformed address) will
    // keep failing the same way each retry until max_attempts is hit,
    // at which point it becomes visible as 'failed' rather than
    // retrying forever.
    throw new Error(`Resend API error ${response.status}: ${detail}`);
  }

  const data = (await response.json()) as { id?: string };
  if (!data.id) {
    throw new Error("Resend API response did not include a message id.");
  }

  return { providerMessageId: data.id };
}
