// Public, unauthenticated endpoint (`verify_jwt = false`) per
// implementation_plan.md Section 8: "checks dependencies without
// returning secrets or personal data." Point an uptime monitor (e.g.
// UptimeRobot, Better Uptime, a status-page check) at this URL and
// alert on a non-200 response — that's the "alerts" half of Section
// 8's "dashboards and alerts" deliverable; get_group_email_activity()
// in 0004_scheduling_email.sql is the in-app half, for organizers.
import { createAdminClient } from "../_shared/supabaseAdmin.ts";

// Tuned for a small pilot deployment (Section 9: "pilot with 2-3 real
// groups"); revisit alongside real usage before a larger rollout.
const PENDING_BACKLOG_THRESHOLD = 200;
const OLDEST_PENDING_SECONDS_THRESHOLD = 60 * 60; // 1 hour
const SCHEDULER_STALE_SECONDS_THRESHOLD = 30 * 60; // 30 minutes — cron runs every 10-15

type HealthRow = {
  pending_outbox_count: number | null;
  oldest_pending_seconds: number | null;
  permanently_failed_count: number | null;
  last_scheduler_run_at: string | null;
  seconds_since_last_scheduler_run: number | null;
};

Deno.serve(async () => {
  const admin = createAdminClient();
  const { data, error } = await admin.rpc("get_operational_health").maybeSingle();

  if (error || !data) {
    return jsonResponse(503, {
      status: "error",
      problems: ["could not read operational health from the database"],
      detail: error?.message,
    });
  }

  const health = data as HealthRow;
  const problems: string[] = [];

  if ((health.pending_outbox_count ?? 0) > PENDING_BACKLOG_THRESHOLD) {
    problems.push("email outbox backlog is larger than expected");
  }
  if ((health.oldest_pending_seconds ?? 0) > OLDEST_PENDING_SECONDS_THRESHOLD) {
    problems.push("the oldest pending email has been waiting too long");
  }
  if ((health.permanently_failed_count ?? 0) > 0) {
    problems.push("there are permanently failed emails needing attention");
  }
  if (
    health.last_scheduler_run_at === null ||
    (health.seconds_since_last_scheduler_run ?? Infinity) > SCHEDULER_STALE_SECONDS_THRESHOLD
  ) {
    problems.push("the scheduler has not completed a run recently");
  }

  const status = problems.length === 0 ? "ok" : "degraded";

  return jsonResponse(status === "ok" ? 200 : 503, {
    status,
    problems,
    pending_outbox_count: health.pending_outbox_count,
    oldest_pending_seconds: health.oldest_pending_seconds,
    permanently_failed_count: health.permanently_failed_count,
    last_scheduler_run_at: health.last_scheduler_run_at,
    seconds_since_last_scheduler_run: health.seconds_since_last_scheduler_run,
  });
});

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
