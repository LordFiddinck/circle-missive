// Invoked on a timer (see supabase/cron-setup.sql) with
// `verify_jwt = false` in supabase/config.toml — see
// _shared/cronAuth.ts for why. Each invocation claims a small batch
// of due email_outbox rows, sends each through Resend, and reports
// success or failure back so 0004_scheduling_email.sql's retry/dedupe
// logic can take over from there.
import { createAdminClient } from "../_shared/supabaseAdmin.ts";
import { requireCronSecret } from "../_shared/cronAuth.ts";
import { renderEmail, type OutboxRow } from "../_shared/emailTemplates.ts";
import { sendViaResend } from "../_shared/resend.ts";

const BATCH_SIZE = 25;

Deno.serve(async (req) => {
  const authError = requireCronSecret(req);
  if (authError) return authError;

  const admin = createAdminClient();

  const { data: batch, error: claimError } = await admin.rpc("claim_outbox_batch", {
    p_limit: BATCH_SIZE,
  });

  if (claimError) {
    return new Response(JSON.stringify({ error: claimError.message }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  const rows = (batch ?? []) as (OutboxRow & { id: string; recipient_user_id: string | null })[];
  let sent = 0;
  let failed = 0;

  for (const row of rows) {
    try {
      // The unsubscribe token lives on email_preferences, not the
      // outbox payload — invitees (recipient_user_id null) simply get
      // no unsubscribe link, since invitation mail is transactional
      // and they have no preferences row yet anyway.
      let unsubscribeToken: string | null = null;
      if (row.recipient_user_id) {
        const { data: prefs } = await admin
          .from("email_preferences")
          .select("unsubscribe_token")
          .eq("user_id", row.recipient_user_id)
          .maybeSingle();
        unsubscribeToken = (prefs?.unsubscribe_token as string | undefined) ?? null;
      }

      const rendered = renderEmail(row, unsubscribeToken);
      const result = await sendViaResend({
        to: row.recipient_email,
        subject: rendered.subject,
        html: rendered.html,
        text: rendered.text,
      });

      const { error: sentError } = await admin.rpc("mark_outbox_sent", {
        p_id: row.id,
        p_provider_message_id: result.providerMessageId,
      });
      if (sentError) throw sentError;

      sent += 1;
    } catch (err) {
      failed += 1;
      const message = err instanceof Error ? err.message : String(err);
      await admin.rpc("mark_outbox_failed", { p_id: row.id, p_error: message });
    }
  }

  return new Response(JSON.stringify({ claimed: rows.length, sent, failed }), {
    headers: { "content-type": "application/json" },
  });
});
