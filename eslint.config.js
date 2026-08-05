import js from "@eslint/js";
import tseslint from "@typescript-eslint/eslint-plugin";
import tsParser from "@typescript-eslint/parser";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import jsxA11y from "eslint-plugin-jsx-a11y";
import globals from "globals";

export default [
  js.configs.recommended,
  {
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module",
        ecmaFeatures: { jsx: true },
      },
      globals: {
        ...globals.browser,
        ...globals.es2021,
      },
    },
    plugins: {
      "@typescript-eslint": tseslint,
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
      "jsx-a11y": jsxA11y,
    },
    rules: {
      ...tseslint.configs.recommended.rules,
      ...reactHooks.configs.recommended.rules,
      ...jsxA11y.configs.recommended.rules,
      "react-refresh/only-export-components": [
        "warn",
        { allowConstantExport: true },
      ],
    },
  },
  {
    files: ["*.config.{js,ts}"],
    languageOptions: {
      globals: {
        ...globals.node,
      },
    },
  },
  {
    // supabase/functions/** runs on Deno (Supabase Edge Functions), not
    // in the browser or Node — it uses globals (`Deno`) and import
    // specifiers (`npm:package@version`) this config doesn't model.
    // `deno lint`/`deno check` are the appropriate tools for that
    // directory; see its own README for local development commands.
    ignores: ["dist/**", "node_modules/**", "supabase/functions/**"],
  },
];
