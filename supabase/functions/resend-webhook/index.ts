// Public endpoint (Resend can't send a Supabase JWT, so this needs
// `verify_jwt = false` in supabase/config.toml too) — authorization
// comes entirely from verifying Resend's Svix webhook signature
// below, never skipped. Configure this URL in the Resend dashboard's
// webhook settings and copy the signing secret it gives you into the
// `RESEND_WEBHOOK_SECRET` project secret.
//
// Signature scheme: https://docs.svix.com/receiving/verifying-payloads/how-manual-verification-works
// (Resend webhooks are Svix-signed). Implemented by hand rather than
// pulling in the svix package, since the algorithm is a few lines of
// HMAC-SHA256 and this avoids an extra dependency in an Edge Function.
import { createAdminClient } from "../_shared/supabaseAdmin.ts";

const TOLERANCE_SECONDS = 5 * 60;

const RESEND_EVENT_TO_OUTBOX_EVENT: Record<string, string> = {
  "email.delivered": "delivered",
  "email.bounced": "bounced",
  "email.complained": "complained",
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const rawBody = await req.text();

  const verified = await verifySvixSignature(req, rawBody);
  if (!verified) {
    return new Response("Invalid signature", { status: 401 });
  }

  let event: { type?: string; created_at?: string; data?: { email_id?: string } };
  try {
    event = JSON.parse(rawBody);
  } catch {
    return new Response("Invalid JSON body", { status: 400 });
  }

  const mappedEventType = event.type ? RESEND_EVENT_TO_OUTBOX_EVENT[event.type] : undefined;
  const providerMessageId = event.data?.email_id;

  // Event types we don't track (e.g. email.sent, email.opened) are
  // acknowledged with 200 rather than rejected, so Resend doesn't
  // retry delivering something we're intentionally ignoring.
  if (mappedEventType && providerMessageId) {
    const admin = createAdminClient();
    const { error } = await admin.rpc("record_email_delivery_event", {
      p_provider_message_id: providerMessageId,
      p_event_type: mappedEventType,
      p_occurred_at: event.created_at ?? new Date().toISOString(),
    });
    if (error) {
      // A 500 tells Resend to retry the webhook later rather than
      // silently losing a bounce/complaint we failed to record.
      return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    }
  }

  return new Response("ok", { status: 200 });
});

async function verifySvixSignature(req: Request, rawBody: string): Promise<boolean> {
  const secretRaw = Deno.env.get("RESEND_WEBHOOK_SECRET");
  if (!secretRaw) return false;

  const svixId = req.headers.get("svix-id");
  const svixTimestamp = req.headers.get("svix-timestamp");
  const svixSignature = req.headers.get("svix-signature");
  if (!svixId || !svixTimestamp || !svixSignature) return false;

  const timestampSeconds = Number(svixTimestamp);
  if (!Number.isFinite(timestampSeconds)) return false;
  if (Math.abs(Date.now() / 1000 - timestampSeconds) > TOLERANCE_SECONDS) {
    return false; // too old (or a replayed event) — reject rather than process
  }

  const secretBytes = base64Decode(secretRaw.replace(/^whsec_/, ""));
  const signedContent = `${svixId}.${svixTimestamp}.${rawBody}`;

  const key = await crypto.subtle.importKey(
    "raw",
    secretBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signatureBytes = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signedContent));
  const expectedSignature = base64Encode(new Uint8Array(signatureBytes));

  // The header can carry multiple "v1,<signature>" pairs (space
  // separated) across a secret rotation; any match is acceptable.
  const candidates = svixSignature
    .split(" ")
    .map((part) => part.split(",")[1])
    .filter((value): value is string => Boolean(value));

  return candidates.some((candidate) => timingSafeEqual(candidate, expectedSignature));
}

function base64Decode(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64Encode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}
