// Invoked on a timer (every 10-15 minutes, per implementation_plan.md
// Section 5) with `verify_jwt = false` (see _shared/cronAuth.ts). All
// of the actual decision-making lives in the scheduler_tick() SQL
// function — this wrapper exists only because Supabase Cron can't
// wake up a plain SQL function on its own without either pg_net (see
// supabase/cron-setup.sql, which uses exactly that to call this
// function) or the `pg_cron` "call SQL directly" option; routing
// through an Edge Function keeps this endpoint reusable for manual
// triggering (e.g. from the operations runbook) and consistent with
// how email-worker is invoked.
import { createAdminClient } from "../_shared/supabaseAdmin.ts";
import { requireCronSecret } from "../_shared/cronAuth.ts";

const BATCH_SIZE = 50;

Deno.serve(async (req) => {
  const authError = requireCronSecret(req);
  if (authError) return authError;

  const admin = createAdminClient();
  const { data, error } = await admin.rpc("scheduler_tick", { p_batch_size: BATCH_SIZE });

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  // scheduler_tick() is declared `returns table (...)`, which
  // supabase-js surfaces as a one-row array.
  const result = Array.isArray(data) ? data[0] : data;

  return new Response(
    JSON.stringify(result ?? { cycles_examined: 0, emails_enqueued: 0 }),
    { headers: { "content-type": "application/json" } },
  );
});
