import { useGroupEmailActivity } from "./queries";

type EmailActivityProps = {
  groupId: string;
};

const STATUS_LABELS: Record<string, string> = {
  pending: "Queued",
  sending: "Sending",
  sent: "Sent",
  skipped: "Skipped (opted out)",
  failed: "Failed",
};

export function EmailActivity({ groupId }: EmailActivityProps) {
  const activity = useGroupEmailActivity(groupId);

  if (activity.isLoading) {
    return <p role="status">Loading email activity…</p>;
  }

  if (activity.isError) {
    return (
      <p role="alert">Could not load this group&rsquo;s email activity.</p>
    );
  }

  if (!activity.data || activity.data.length === 0) {
    return <p>No email has been sent for this group yet.</p>;
  }

  const hasFailures = activity.data.some(
    (row) => row.status === "failed" && row.message_count > 0,
  );

  return (
    <>
      {hasFailures ? (
        <p role="alert">
          Some email for this group has permanently failed to send. Check the
          outbox in Supabase, or ask a maintainer.
        </p>
      ) : null}
      <table>
        <caption className="sr-only">
          Email activity for this group, by template and status
        </caption>
        <thead>
          <tr>
            <th scope="col">Notification</th>
            <th scope="col">Status</th>
            <th scope="col">Count</th>
            <th scope="col">Most recent</th>
          </tr>
        </thead>
        <tbody>
          {activity.data.map((row) => (
            <tr key={`${row.template}:${row.status}`}>
              <td>{row.template.replaceAll("_", " ")}</td>
              <td>{STATUS_LABELS[row.status] ?? row.status}</td>
              <td>{row.message_count}</td>
              <td>{new Date(row.most_recent).toLocaleString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}
