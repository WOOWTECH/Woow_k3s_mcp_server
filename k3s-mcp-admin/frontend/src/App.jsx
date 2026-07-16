import React from "react";
import { Routes, Route, Navigate, Outlet } from "react-router-dom";
import { getToken } from "./api";
import Sidebar from "./components/Sidebar";
import Dashboard from "./pages/Dashboard";
import ToolManager from "./pages/ToolManager";
import TokenManager from "./pages/TokenManager";
import LogViewer from "./pages/LogViewer";
import ClusterOverview from "./pages/ClusterOverview";
import SettingsPage from "./pages/SettingsPage";
import LoginPage from "./pages/LoginPage";

function ProtectedRoute() {
  const token = getToken();
  if (!token) {
    return <Navigate to="/login" replace />;
  }
  return <Outlet />;
}

function AppLayout() {
  return (
    <div className="flex min-h-screen bg-gray-950">
      <Sidebar />
      <main className="flex-1 p-6 overflow-auto">
        <Outlet />
      </main>
    </div>
  );
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route element={<ProtectedRoute />}>
        <Route element={<AppLayout />}>
          <Route path="/" element={<Dashboard />} />
          <Route path="/tools" element={<ToolManager />} />
          <Route path="/tokens" element={<TokenManager />} />
          <Route path="/logs" element={<LogViewer />} />
          <Route path="/cluster" element={<ClusterOverview />} />
          <Route path="/settings" element={<SettingsPage />} />
        </Route>
      </Route>
    </Routes>
  );
}
