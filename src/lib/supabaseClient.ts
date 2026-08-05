import { createClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";

// Only the project URL and the publishable ("anon") key belong here.
// These are identifiers, not administrator secrets — Row Level Security
// is the real access boundary (see implementation plan, Section 3 and 4).
// Never import the service-role key, Resend key, or Groq key into
// anything that ships to the browser.
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as
  string | undefined;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    "Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY. Copy .env.example to .env.local and fill in your Supabase project's values.",
  );
}

export const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});
