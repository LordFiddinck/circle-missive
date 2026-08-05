// Renders every template listed in implementation_plan.md Section 6
// into a subject/html/text triple. Every message follows the plan's
// rule of thumb: the group name, one clear action, the relevant
// deadline (always shown in UTC, since a member's local timezone
// isn't reliably known server-side), why the recipient received it,
// and preference/help links — and never private answer text, only a
// link to the authenticated site.

export type OutboxRow = {
  id: string;
  template: string;
  category: "transactional" | "reminders" | "announcements";
  payload: Record<string, unknown>;
  group_id: string | null;
  recipient_email: string;
};

export type RenderedEmail = { subject: string; html: string; text: string };

// Trailing slash trimmed so every link below can safely do
// `${APP_BASE_URL}/#/...` without risking a double slash.
const APP_BASE_URL = (Deno.env.get("APP_BASE_URL") ?? "https://example.invalid").replace(/\/+$/, "");

function groupUrl(groupId: string | null): string {
  return groupId ? `${APP_BASE_URL}/#/groups/${groupId}` : APP_BASE_URL;
}

function cycleUrl(groupId: string | null, cycleId: unknown): string {
  return groupId && typeof cycleId === "string"
    ? `${APP_BASE_URL}/#/groups/${groupId}/cycles/${cycleId}`
    : groupUrl(groupId);
}

function archiveUrl(groupId: string | null): string {
  return groupId ? `${APP_BASE_URL}/#/groups/${groupId}/archive` : APP_BASE_URL;
}

function inviteUrl(token: unknown): string {
  return `${APP_BASE_URL}/#/invite/${String(token)}`;
}

function accountUrl(): string {
  return `${APP_BASE_URL}/#/account`;
}

function unsubscribeUrl(token: string, category: "reminders" | "announcements"): string {
  return `${APP_BASE_URL}/#/unsubscribe/${token}/${category}`;
}

function formatDate(value: unknown): string {
  if (typeof value !== "string") return "soon";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return "soon";
  return (
    parsed.toLocaleString("en-US", {
      dateStyle: "medium",
      timeStyle: "short",
      timeZone: "UTC",
    }) + " UTC"
  );
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

type EnvelopeInput = {
  subject: string;
  heading: string;
  bodyLines: string[];
  ctaLabel: string;
  ctaUrl: string;
  reason: string;
  /** null for mandatory mail (invites, phase-open notices, deadline changes) — see 0004's category comments. */
  unsubscribeHref: string | null;
};

function renderEnvelope(input: EnvelopeInput): RenderedEmail {
  const paragraphsHtml = input.bodyLines.map((line) => `<p>${line}</p>`).join("\n      ");

  const footerLinksHtml = [`<a href="${accountUrl()}">Email preferences</a>`];
  if (input.unsubscribeHref) {
    footerLinksHtml.push(`<a href="${input.unsubscribeHref}">Unsubscribe from this kind of email</a>`);
  }

  const html = `
    <div style="font-family: -apple-system, sans-serif; max-width: 480px; margin: 0 auto; color: #1a1a1a;">
      <h1 style="font-size: 18px; margin-bottom: 12px;">${input.heading}</h1>
      ${paragraphsHtml}
      <p style="margin: 20px 0;">
        <a href="${input.ctaUrl}"
           style="display:inline-block;padding:10px 18px;background:#1a1a1a;color:#fff;text-decoration:none;border-radius:4px;">
          ${input.ctaLabel}
        </a>
      </p>
      <p style="color:#666; font-size:13px;">${input.reason}</p>
      <p style="color:#999; font-size:12px;">${footerLinksHtml.join(" &middot; ")}</p>
    </div>
  `.trim();

  const textFooterLines = [`Email preferences: ${accountUrl()}`];
  if (input.unsubscribeHref) {
    textFooterLines.push(`Unsubscribe from this kind of email: ${input.unsubscribeHref}`);
  }

  const text = [
    input.heading,
    "",
    ...input.bodyLines.map((line) => line.replace(/<[^>]+>/g, "")),
    "",
    `${input.ctaLabel}: ${input.ctaUrl}`,
    "",
    input.reason,
    "",
    ...textFooterLines,
  ].join("\n");

  return { subject: input.subject, html, text };
}

/**
 * `unsubscribeToken` is looked up separately by the caller (it lives
 * on email_preferences, not the outbox payload) and is null for
 * invitees, who aren't members yet and have no preferences row.
 */
export function renderEmail(row: OutboxRow, unsubscribeToken: string | null): RenderedEmail {
  const payload = row.payload ?? {};
  const groupName = typeof payload.group_name === "string" ? escapeHtml(payload.group_name) : "your group";

  const optionalUnsubscribeHref =
    unsubscribeToken && row.category !== "transactional"
      ? unsubscribeUrl(unsubscribeToken, row.category)
      : null;

  switch (row.template) {
    case "group_invitation":
      return renderEnvelope({
        subject: `${groupName} invited you to Circle Missive`,
        heading: `You're invited to ${groupName}`,
        bodyLines: [
          `Someone from ${groupName} invited you to join their private, recurring question-and-answer circle.`,
          `This invite link expires ${formatDate(payload.expires_at)}.`,
        ],
        ctaLabel: "Accept invitation",
        ctaUrl: inviteUrl(payload.invite_token),
        reason: `You're receiving this because someone invited ${escapeHtml(row.recipient_email)} to ${groupName}.`,
        unsubscribeHref: null,
      });

    case "invitation_reminder":
      return renderEnvelope({
        subject: `Reminder: your invite to ${groupName}`,
        heading: `Your invite to ${groupName} is waiting`,
        bodyLines: [
          `This is a reminder that you have a pending invitation to ${groupName}.`,
          `This invite link expires ${formatDate(payload.expires_at)}.`,
        ],
        ctaLabel: "Accept invitation",
        ctaUrl: inviteUrl(payload.invite_token),
        reason: `You're receiving this because someone invited ${escapeHtml(row.recipient_email)} to ${groupName}.`,
        unsubscribeHref: null,
      });

    case "question_collection_opened":
      return renderEnvelope({
        subject: `${groupName}: suggest a question for this cycle`,
        heading: `A new cycle is open in ${groupName}`,
        bodyLines: [
          `It's time to suggest questions for this cycle of ${groupName}.`,
          `Question suggestions close ${formatDate(payload.question_closes_at)}.`,
        ],
        ctaLabel: "Suggest a question",
        ctaUrl: cycleUrl(row.group_id, payload.cycle_id),
        reason: `You're receiving this because you're a member of ${groupName}.`,
        unsubscribeHref: null,
      });

    case "question_collection_ending_soon":
      return renderEnvelope({
        subject: `${groupName}: question suggestions close soon`,
        heading: `Question suggestions close soon in ${groupName}`,
        bodyLines: [`Question suggestions for this cycle close ${formatDate(payload.question_closes_at)}.`],
        ctaLabel: "Suggest a question",
        ctaUrl: cycleUrl(row.group_id, payload.cycle_id),
        reason: `You're receiving this because you're a member of ${groupName}.`,
        unsubscribeHref: optionalUnsubscribeHref,
      });

    case "question_phase_overdue":
      return renderEnvelope({
        subject: `${groupName} needs you to finalize questions`,
        heading: `${groupName}'s question phase needs your attention`,
        bodyLines: [
          `Question suggestions for this cycle closed ${formatDate(payload.question_closes_at)}, but the final question set hasn't been chosen yet.`,
          `As an organizer, you can finalize the questions whenever you're ready.`,
        ],
        ctaLabel: "Finalize questions",
        ctaUrl: cycleUrl(row.group_id, payload.cycle_id),
        reason: `You're receiving this because you organize ${groupName}.`,
        unsubscribeHref: null,
      });

    case "answering_opened":
      return renderEnvelope({
        subject: `${groupName}: it's time to answer`,
        heading: `Questions are ready in ${groupName}`,
        bodyLines: [
          `The final questions for this cycle are set — it's time to write your answers.`,
          `Answers are due ${formatDate(payload.answer_due_at)}.`,
        ],
        ctaLabel: "Write your answers",
        ctaUrl: cycleUrl(row.group_id, payload.cycle_id),
        reason: `You're receiving this because you're a member of ${groupName}.`,
        unsubscribeHref: null,
      });

    case "answer_deadline_reminder":
      return renderEnvelope({
        subject: `${groupName}: your answers are due soon`,
        heading: `Your answers in ${groupName} are due soon`,
        bodyLines: [
          `Answers for this cycle are due ${formatDate(payload.answer_due_at)}, and you haven't submitted yet.`,
        ],
        ctaLabel: "Finish your answers",
        ctaUrl: cycleUrl(row.group_id, payload.cycle_id),
        reason: `You're receiving this because you're a member of ${groupName} with unsubmitted answers.`,
        unsubscribeHref: optionalUnsubscribeHref,
      });

    case "answer_final_reminder":
      return renderEnvelope({
        subject: `${groupName}: last chance to answer`,
        heading: `Last chance to answer in ${groupName}`,
        bodyLines: [
          `Answers for this cycle are due ${formatDate(payload.answer_due_at)} — very soon — and you haven't submitted yet.`,
        ],
        ctaLabel: "Finish your answers",
        ctaUrl: cycleUrl(row.group_id, payload.cycle_id),
        reason: `You're receiving this because you're a member of ${groupName} with unsubmitted answers.`,
        unsubscribeHref: optionalUnsubscribeHref,
      });

    case "issue_published":
      return renderEnvelope({
        subject: `${groupName}'s new issue is ready to read`,
        heading: `${groupName}'s latest issue is out`,
        bodyLines: [
          typeof payload.sequence_no === "number"
            ? `Cycle #${payload.sequence_no} of ${groupName} has just been published.`
            : `A new cycle of ${groupName} has just been published.`,
        ],
        ctaLabel: "Read the issue",
        ctaUrl: archiveUrl(row.group_id),
        reason: `You're receiving this because you're a member of ${groupName}.`,
        unsubscribeHref: optionalUnsubscribeHref,
      });

    case "cycle_schedule_changed":
      return renderEnvelope({
        subject: `${groupName}: this cycle's schedule changed`,
        heading: `${groupName}'s cycle timing changed`,
        bodyLines: [
          `An organizer changed this cycle's deadline. The new date is ${formatDate(payload.new_due_at)}.`,
        ],
        ctaLabel: "View the group",
        ctaUrl: cycleUrl(row.group_id, payload.cycle_id),
        reason: `You're receiving this because you're a member of ${groupName}.`,
        unsubscribeHref: null,
      });

    case "membership_changed":
      return renderEnvelope({
        subject: `Your membership in ${groupName} changed`,
        heading: `Your membership in ${groupName} changed`,
        bodyLines: [
          payload.change === "removed"
            ? `You've been removed from ${groupName} by an organizer.`
            : `Your membership in ${groupName} was updated.`,
        ],
        ctaLabel: "Visit Circle Missive",
        ctaUrl: APP_BASE_URL,
        reason: "You're receiving this because of a membership change affecting your account.",
        unsubscribeHref: null,
      });

    default:
      // Should be unreachable — every template inserted by
      // 0004_scheduling_email.sql is handled above — but a fallback
      // keeps a typo in a future template name from crashing the
      // worker outright; it'll show up as an odd-looking but
      // deliverable email instead, and templates are always visible
      // in email_outbox for a maintainer to notice and fix.
      return renderEnvelope({
        subject: `An update from ${groupName}`,
        heading: `An update from ${groupName}`,
        bodyLines: [`There's an update in ${groupName}.`],
        ctaLabel: "View the group",
        ctaUrl: groupUrl(row.group_id),
        reason: "You're receiving this because you're a member of this group.",
        unsubscribeHref: optionalUnsubscribeHref,
      });
  }
}
