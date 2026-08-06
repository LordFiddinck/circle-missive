// Hand-written types mirroring supabase/migrations/0001 and 0002.
// If a real `supabase gen types` run ever diverges from this file,
// prefer the generated output — this exists so the client is typed
// without needing a live project during local development.

export type MembershipRole = "organizer" | "member";
export type MembershipStatus = "active" | "removed" | "left";
export type InvitationStatus = "pending" | "accepted" | "revoked" | "expired";
export type CyclePhase =
  "question_collection" | "answering" | "published" | "skipped";
export type EmailOutboxStatus =
  "pending" | "sending" | "sent" | "skipped" | "failed";
export type EmailCategory = "transactional" | "reminders" | "announcements";

export type Profile = {
  user_id: string;
  display_name: string;
  locale: string;
  created_at: string;
  updated_at: string;
};

export type Group = {
  id: string;
  name: string;
  timezone: string;
  interval_days: number;
  question_phase_days: number;
  answer_phase_days: number;
  next_cycle_at: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
};

export type Membership = {
  id: string;
  group_id: string;
  user_id: string;
  role: MembershipRole;
  status: MembershipStatus;
  invited_by: string | null;
  joined_at: string;
  left_at: string | null;
};

export type Invitation = {
  id: string;
  group_id: string;
  email_normalized: string;
  token_hash: string;
  status: InvitationStatus;
  invited_by: string;
  expires_at: string;
  accepted_by: string | null;
  accepted_at: string | null;
  created_at: string;
};

export type AuditEvent = {
  id: string;
  group_id: string | null;
  actor_id: string | null;
  event_type: string;
  metadata: Record<string, unknown>;
  created_at: string;
};

export type Cycle = {
  id: string;
  group_id: string;
  sequence_no: number;
  phase: CyclePhase;
  question_opens_at: string;
  question_closes_at: string | null;
  answer_opens_at: string | null;
  answer_due_at: string | null;
  published_at: string | null;
  next_action_at: string | null; // drives Phase 4's scheduler_tick()
  created_by: string;
  created_at: string;
  updated_at: string;
};

export type QuestionProposal = {
  id: string;
  cycle_id: string;
  author_id: string;
  text: string;
  created_at: string;
  updated_at: string;
};

export type CycleQuestion = {
  id: string;
  cycle_id: string;
  proposal_id: string | null;
  text: string;
  position: number;
  created_at: string;
};

export type Answer = {
  id: string;
  question_id: string;
  author_id: string;
  body: string;
  revision: number;
  submitted_at: string | null;
  created_at: string;
  updated_at: string;
};

export type IssueEntry = {
  id: string;
  cycle_id: string;
  question_id: string;
  author_id: string;
  body: string;
  answer_revision: number;
  is_late: boolean;
  published_at: string;
};

export type CycleProgress = {
  user_id: string;
  display_name: string;
  questions_total: number;
  questions_answered: number;
  submitted: boolean;
  submitted_at: string | null;
};

export type EmailPreferences = {
  user_id: string;
  reminders_enabled: boolean;
  announcements_enabled: boolean;
  suppressed: boolean;
  unsubscribe_token: string;
  updated_at: string;
};

export type EmailActivitySummary = {
  template: string;
  status: EmailOutboxStatus;
  message_count: number;
  most_recent: string;
};

type TableDef<Row, Update = Partial<Row>, Insert = never> = {
  Row: Row;
  Insert: Insert; // most writes in this schema go through an RPC instead
  Update: Update;
  Relationships: [];
};

export type Database = {
  public: {
    Tables: {
      profiles: TableDef<
        Profile,
        Partial<Pick<Profile, "display_name" | "locale">>
      >;
      groups: TableDef<
        Group,
        Partial<
          Pick<
            Group,
            | "name"
            | "timezone"
            | "interval_days"
            | "question_phase_days"
            | "answer_phase_days"
            | "next_cycle_at"
          >
        >
      >;
      memberships: TableDef<Membership, never>;
      invitations: TableDef<Invitation, never>;
      audit_events: TableDef<AuditEvent, never>;
      cycles: TableDef<Cycle, never>;
      question_proposals: TableDef<
        QuestionProposal,
        Partial<Pick<QuestionProposal, "text">>,
        Pick<QuestionProposal, "cycle_id" | "author_id" | "text">
      >;
      cycle_questions: TableDef<CycleQuestion, never>;
      answers: TableDef<Answer, Partial<Pick<Answer, "body">>>;
      issue_entries: TableDef<IssueEntry, never>;
      email_preferences: TableDef<
        EmailPreferences,
        Partial<
          Pick<EmailPreferences, "reminders_enabled" | "announcements_enabled">
        >
      >;
    };
    Views: Record<string, never>;
    Functions: {
      create_group: {
        Args: {
          p_name: string;
          p_timezone?: string;
          p_interval_days?: number;
          p_question_phase_days?: number;
          p_answer_phase_days?: number;
        };
        Returns: Group;
      };
      create_invitation: {
        Args: { p_group_id: string; p_email: string };
        Returns: { invitation_id: string; token: string; expires_at: string }[];
      };
      resend_invitation: {
        Args: { p_invitation_id: string };
        Returns: { token: string; expires_at: string }[];
      };
      revoke_invitation: {
        Args: { p_invitation_id: string };
        Returns: undefined;
      };
      get_invitation_preview: {
        Args: { p_token: string };
        Returns: {
          group_name: string;
          inviter_display_name: string;
          email_normalized: string;
          status: InvitationStatus;
          expires_at: string;
        }[];
      };
      accept_invitation: {
        Args: { p_token: string };
        Returns: { accepted_group_id: string }[];
      };
      list_my_pending_invitations: {
        Args: Record<string, never>;
        Returns: {
          invitation_id: string;
          group_id: string;
          group_name: string;
          inviter_display_name: string;
          expires_at: string;
        }[];
      };
      accept_invitation_by_id: {
        Args: { p_invitation_id: string };
        Returns: { accepted_group_id: string }[];
      };
      remove_member: {
        Args: { p_group_id: string; p_user_id: string };
        Returns: undefined;
      };
      leave_group: {
        Args: { p_group_id: string };
        Returns: undefined;
      };
      set_member_role: {
        Args: { p_group_id: string; p_user_id: string; p_role: MembershipRole };
        Returns: undefined;
      };
      start_cycle: {
        Args: { p_group_id: string };
        Returns: Cycle;
      };
      finalize_questions: {
        Args: { p_cycle_id: string; p_proposal_ids: string[] };
        Returns: Cycle;
      };
      submit_answers: {
        Args: { p_cycle_id: string };
        Returns: undefined;
      };
      reopen_submission: {
        Args: { p_cycle_id: string; p_user_id: string };
        Returns: undefined;
      };
      change_cycle_deadline: {
        Args: { p_cycle_id: string; p_new_due_at: string };
        Returns: Cycle;
      };
      publish_cycle: {
        Args: { p_cycle_id: string };
        Returns: Cycle;
      };
      submit_late_answer: {
        Args: { p_question_id: string; p_body: string };
        Returns: undefined;
      };
      skip_cycle: {
        Args: { p_cycle_id: string };
        Returns: Cycle;
      };
      get_cycle_progress: {
        Args: { p_cycle_id: string };
        Returns: CycleProgress[];
      };
      get_group_email_activity: {
        Args: { p_group_id: string };
        Returns: EmailActivitySummary[];
      };
      unsubscribe_by_token: {
        Args: { p_token: string; p_category: "reminders" | "announcements" };
        Returns: undefined;
      };
    };
    Enums: {
      membership_role: MembershipRole;
      membership_status: MembershipStatus;
      invitation_status: InvitationStatus;
      cycle_phase: CyclePhase;
      email_outbox_status: EmailOutboxStatus;
    };
  };
};
