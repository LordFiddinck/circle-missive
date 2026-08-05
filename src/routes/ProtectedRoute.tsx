import type { ReactNode } from "react";
import { Navigate } from "react-router-dom";
import { useSession } from "@/lib/useSession";

type ProtectedRouteProps = {
  children: ReactNode;
};

export function ProtectedRoute({ children }: ProtectedRouteProps) {
  const { session, loading } = useSession();

  if (loading) {
    return (
      <p role="status" aria-live="polite">
        Checking your sign-in status…
      </p>
    );
  }

  if (!session) {
    return <Navigate to="/sign-in" replace />;
  }

  return <>{children}</>;
}
