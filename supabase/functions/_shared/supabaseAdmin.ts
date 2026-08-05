// Every Phase 4 Edge Function needs a Supabase client authenticated as
// `service_role` — the whole reason these run server-side instead of
// in the browser. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are
// provided automatically to every Edge Function by the Supabase
// platform; they don't need to be set as project secrets.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.0";

export function createAdminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!url || !serviceRoleKey) {
    throw new Error(
      "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be available in the function environment.",
    );
  }

  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
