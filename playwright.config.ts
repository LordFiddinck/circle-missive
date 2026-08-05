import { defineConfig, devices } from "@playwright/test";

// Scaffolding only for now — see e2e/README.md for what's covered and
// what isn't yet. `npm run e2e` needs a running Supabase project (local
// or hosted) with VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY set, same
// as `npm run dev`.
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 2 : 0,
  reporter: "list",
  use: {
    baseURL: "http://localhost:5173",
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "npm run dev",
    url: "http://localhost:5173",
    reuseExistingServer: !process.env.CI,
  },
});
