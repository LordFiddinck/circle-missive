import { Link } from "react-router-dom";

// Referenced by the plan's landing/sign-in screen ("privacy and terms
// links", Section 2) and kept available from the signed-in account area
// too. These routes are intentionally outside <ProtectedRoute> — people
// should be able to read them before they ever sign in.
export function LegalFooter() {
  return (
    <footer>
      <nav aria-label="Legal and help">
        <Link to="/privacy">Privacy</Link>
        {" · "}
        <Link to="/terms">Terms</Link>
        {" · "}
        <Link to="/help">Help</Link>
      </nav>
    </footer>
  );
}
