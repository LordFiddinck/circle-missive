import { useEffect, useRef } from "react";
import { Route, Routes, useLocation, useNavigate } from "react-router-dom";
import SignIn from "./routes/SignIn";
import Dashboard from "./routes/Dashboard";
import Account from "./routes/Account";
import Privacy from "./routes/Privacy";
import Terms from "./routes/Terms";
import Help from "./routes/Help";
import Unsubscribe from "./routes/Unsubscribe";
import AcceptInvite from "./routes/AcceptInvite";
import NewGroup from "./routes/groups/NewGroup";
import GroupDetail from "./routes/groups/GroupDetail";
import GroupArchive from "./routes/groups/GroupArchive";
import CycleDetail from "./routes/groups/CycleDetail";
import { ProtectedRoute } from "./routes/ProtectedRoute";

export default function App() {
  const navigate = useNavigate();
  const location = useLocation();
  const mainRef = useRef<HTMLDivElement>(null);
  const isFirstRender = useRef(true);

  // WCAG 2.4.1 (Bypass Blocks) / 4.1.3 (Status Messages): a hash-routed
  // single-page app never does a real navigation, so the browser never
  // moves keyboard/screen-reader focus for us. Move it to the routed
  // content on every path change (but not on first load, where the
  // browser's own initial focus is fine) so a keyboard or screen-reader
  // user isn't left on a link/button from the previous screen.
  useEffect(() => {
    if (isFirstRender.current) {
      isFirstRender.current = false;
      return;
    }
    mainRef.current?.focus();
  }, [location.pathname]);

  // A magic-link sign-in triggered from the invite-acceptance screen
  // redirects back here carrying the invite token as a query param
  // (?invite=TOKEN) rather than as part of the hash — Supabase appends
  // its own auth tokens as a URL fragment, which would otherwise
  // collide with HashRouter's use of "#". Forward it to the real route.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const inviteToken = params.get("invite");
    if (!inviteToken) return;

    params.delete("invite");
    const remainingSearch = params.toString();
    const cleanedUrl =
      window.location.pathname + (remainingSearch ? `?${remainingSearch}` : "");
    window.history.replaceState(null, "", cleanedUrl);
    navigate(`/invite/${inviteToken}`, { replace: true });
  }, [navigate]);

  return (
    <>
      <a href="#main-content" className="skip-link">
        Skip to main content
      </a>
      {/* tabIndex=-1: not in tab order, but focusable programmatically so
          the effect above can send focus here on route change. */}
      <div id="main-content" ref={mainRef} tabIndex={-1}>
        <Routes>
          <Route path="/sign-in" element={<SignIn />} />
          <Route path="/privacy" element={<Privacy />} />
          <Route path="/terms" element={<Terms />} />
          <Route path="/help" element={<Help />} />
          <Route path="/invite/:token" element={<AcceptInvite />} />
          <Route
            path="/unsubscribe/:token/:category"
            element={<Unsubscribe />}
          />
          <Route
            path="/"
            element={
              <ProtectedRoute>
                <Dashboard />
              </ProtectedRoute>
            }
          />
          <Route
            path="/account"
            element={
              <ProtectedRoute>
                <Account />
              </ProtectedRoute>
            }
          />
          <Route
            path="/groups/new"
            element={
              <ProtectedRoute>
                <NewGroup />
              </ProtectedRoute>
            }
          />
          <Route
            path="/groups/:groupId"
            element={
              <ProtectedRoute>
                <GroupDetail />
              </ProtectedRoute>
            }
          />
          <Route
            path="/groups/:groupId/archive"
            element={
              <ProtectedRoute>
                <GroupArchive />
              </ProtectedRoute>
            }
          />
          <Route
            path="/groups/:groupId/cycles/:cycleId"
            element={
              <ProtectedRoute>
                <CycleDetail />
              </ProtectedRoute>
            }
          />
        </Routes>
      </div>
    </>
  );
}
