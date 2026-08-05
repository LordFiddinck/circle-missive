// scheduler-tick and email-worker are invoked on a timer (Supabase
// Cron -> pg_net -> HTTP), not by a signed-in user, so they can't rely
// on Supabase's own JWT verification (which is why both functions
// must be deployed with `verify_jwt = false` — see supabase/config.toml
// and supabase/cron-setup.sql). This is the substitute: a shared
// secret only Supabase Cron and a maintainer know, checked as a
// plain bearer token.
export function requireCronSecret(req: Request): Response | null {
  const expected = Deno.env.get("CRON_SECRET");
  if (!expected) {
    return new Response(
      "CRON_SECRET is not configured as a Supabase project secret.",
      { status: 500 },
    );
  }

  const provided = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");

  if (!timingSafeEqual(provided, expected)) {
    return new Response("Unauthorized", { status: 401 });
  }

  return null;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}
