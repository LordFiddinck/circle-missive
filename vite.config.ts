/// <reference types="vitest/config" />
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// If deploying to https://<user>.github.io/<repo>/, set base to "/<repo>/".
// If deploying to a custom domain or a user/org root page, leave it as "/".
const REPO_BASE = process.env.VITE_BASE_PATH ?? "/";

export default defineConfig({
  base: REPO_BASE,
  plugins: [react()],
  resolve: {
    alias: {
      "@": "/src",
    },
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test-setup.ts"],
  },
});
