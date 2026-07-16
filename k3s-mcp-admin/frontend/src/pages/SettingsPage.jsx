import React, { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiGet, apiPost, apiPut } from "../api";
import {
  Server,
  Network,
  Shield,
  RefreshCw,
  RotateCw,
  CheckCircle,
  XCircle,
  AlertTriangle,
  Eye,
  EyeOff,
  Save,
  Loader2,
} from "lucide-react";

// ---------------------------------------------------------------------------
// Shared UI Components
// ---------------------------------------------------------------------------

const inputClass =
  "w-full px-3 py-2 bg-gray-950 border border-gray-700 rounded-lg text-gray-100 placeholder-gray-600 focus:outline-none focus:ring-2 focus:ring-green-500/50 focus:border-green-500/50 text-sm";

function SectionCard({ icon: Icon, title, children }) {
  return (
    <div className="bg-gray-900 border border-gray-800 rounded-lg p-5 space-y-4">
      <div className="flex items-center gap-2">
        <Icon size={18} className="text-green-400" />
        <h3 className="text-lg font-semibold text-gray-200">{title}</h3>
      </div>
      {children}
    </div>
  );
}

function StatusBadge({ running }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${
        running
          ? "bg-green-500/10 text-green-400 border border-green-500/20"
          : "bg-red-500/10 text-red-400 border border-red-500/20"
      }`}
    >
      {running ? (
        <>
          <CheckCircle size={12} /> Running
        </>
      ) : (
        <>
          <XCircle size={12} /> Stopped
        </>
      )}
    </span>
  );
}

function Alert({ type = "info", children }) {
  const styles = {
    success:
      "bg-green-500/10 border-green-500/20 text-green-400",
    error: "bg-red-500/10 border-red-500/20 text-red-400",
    warning:
      "bg-yellow-500/10 border-yellow-500/20 text-yellow-400",
    info: "bg-blue-500/10 border-blue-500/20 text-blue-400",
  };

  return (
    <div
      className={`text-sm border rounded-lg px-3 py-2 ${styles[type] || styles.info}`}
    >
      {children}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Section 1: MCP Server Deployment
// ---------------------------------------------------------------------------

function McpServerSection() {
  const queryClient = useQueryClient();

  const { data: status, isLoading } = useQuery({
    queryKey: ["mcp-status"],
    queryFn: () => apiGet("/api/settings/mcp/status"),
    refetchInterval: 5000,
  });

  const restartMutation = useMutation({
    mutationFn: () => apiPost("/api/settings/mcp/restart"),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["mcp-status"] });
    },
  });

  return (
    <SectionCard icon={Server} title="MCP Server Deployment">
      {isLoading ? (
        <div className="flex items-center gap-2 text-gray-500">
          <RefreshCw size={14} className="animate-spin" />
          Loading status...
        </div>
      ) : (
        <div className="space-y-4">
          {/* Status row */}
          <div className="flex items-center justify-between">
            <StatusBadge running={status?.running} />
            <button
              onClick={() => restartMutation.mutate()}
              disabled={restartMutation.isPending}
              className="inline-flex items-center gap-2 px-3 py-1.5 bg-yellow-600/20 hover:bg-yellow-600/30 border border-yellow-600/30 rounded-lg text-sm text-yellow-400 transition-colors disabled:opacity-50"
            >
              {restartMutation.isPending ? (
                <Loader2 size={14} className="animate-spin" />
              ) : (
                <RotateCw size={14} />
              )}
              Restart
            </button>
          </div>

          {/* Pod Info */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-xs text-gray-500">PID</label>
              <p className="text-sm text-gray-300 font-mono">
                {status?.pid ?? "--"}
              </p>
            </div>
            <div>
              <label className="text-xs text-gray-500">Command</label>
              <p className="text-sm text-gray-300 font-mono truncate" title={status?.command}>
                {status?.command || "--"}
              </p>
            </div>
            <div>
              <label className="text-xs text-gray-500">Port</label>
              <p className="text-sm text-gray-300 font-mono">
                {status?.port ?? "--"}
              </p>
            </div>
            <div>
              <label className="text-xs text-gray-500">Restart Count</label>
              <p className="text-sm text-gray-300 font-mono">
                <span
                  className={
                    (status?.restart_count || 0) > 0
                      ? "text-yellow-400"
                      : ""
                  }
                >
                  {status?.restart_count ?? 0}
                </span>
              </p>
            </div>
          </div>

          {status?.exit_code !== null && status?.exit_code !== undefined && !status?.running && (
            <Alert type="warning">
              Last exit code: {status.exit_code}
            </Alert>
          )}

          {restartMutation.isSuccess && (
            <Alert type="success">{restartMutation.data?.message || "Server restarted"}</Alert>
          )}
          {restartMutation.isError && (
            <Alert type="error">
              Restart failed: {restartMutation.error?.message}
            </Alert>
          )}
        </div>
      )}
    </SectionCard>
  );
}

// ---------------------------------------------------------------------------
// Section 2: Proxy Config
// ---------------------------------------------------------------------------

function ProxySection() {
  const { data: health } = useQuery({
    queryKey: ["health"],
    queryFn: () => apiGet("/api/health"),
    refetchInterval: 30000,
  });

  const proxy = health?.proxy || {};

  return (
    <SectionCard icon={Network} title="Proxy Config">
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <span className="text-sm text-gray-400">Status</span>
          <StatusBadge running={proxy.healthy} />
        </div>
        <div>
          <label className="text-xs text-gray-500">Pod Name</label>
          <p className="text-sm text-gray-300 font-mono">
            {proxy.pod_name || "--"}
          </p>
        </div>
        {health?.tunnel?.url && (
          <div>
            <label className="text-xs text-gray-500">Tunnel URL</label>
            <p className="text-sm text-blue-400 font-mono truncate" title={health.tunnel.url}>
              {health.tunnel.url}
            </p>
          </div>
        )}
      </div>
    </SectionCard>
  );
}

// ---------------------------------------------------------------------------
// Section 3: Admin Password
// ---------------------------------------------------------------------------

function PasswordSection() {
  const queryClient = useQueryClient();
  const [newPassword, setNewPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);

  const { data: settings } = useQuery({
    queryKey: ["settings"],
    queryFn: () => apiGet("/api/settings"),
  });

  const updateMutation = useMutation({
    mutationFn: (password) =>
      apiPut("/api/settings/admin_password", { value: password }),
    onSuccess: () => {
      setNewPassword("");
      queryClient.invalidateQueries({ queryKey: ["settings"] });
    },
  });

  const handleSubmit = (e) => {
    e.preventDefault();
    if (newPassword.length < 4) return;
    updateMutation.mutate(newPassword);
  };

  return (
    <SectionCard icon={Shield} title="Admin Password">
      <div className="space-y-4">
        {/* Current password (masked) */}
        <div>
          <label className="text-xs text-gray-500">Current Password</label>
          <p className="text-sm text-gray-400 font-mono">
            {settings?.admin_password_masked || "(not set)"}
          </p>
        </div>

        {/* New password form */}
        <form onSubmit={handleSubmit} className="space-y-3">
          <div>
            <label className="block text-sm text-gray-400 mb-1">
              New Password
            </label>
            <div className="relative">
              <input
                type={showPassword ? "text" : "password"}
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                placeholder="Enter new password (min 4 chars)"
                className={inputClass}
                minLength={4}
              />
              <button
                type="button"
                onClick={() => setShowPassword((v) => !v)}
                className="absolute right-2 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300"
              >
                {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>

          <button
            type="submit"
            disabled={
              newPassword.length < 4 || updateMutation.isPending
            }
            className="inline-flex items-center gap-2 px-4 py-2 bg-green-600 hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed text-white text-sm font-medium rounded-lg transition-colors"
          >
            {updateMutation.isPending ? (
              <Loader2 size={14} className="animate-spin" />
            ) : (
              <Save size={14} />
            )}
            Update Password
          </button>
        </form>

        {updateMutation.isSuccess && (
          <Alert type="success">
            {updateMutation.data?.message || "Password updated successfully"}
          </Alert>
        )}
        {updateMutation.isError && (
          <Alert type="error">
            Failed to update: {updateMutation.error?.message}
          </Alert>
        )}
      </div>
    </SectionCard>
  );
}

// ---------------------------------------------------------------------------
// Main Settings Page
// ---------------------------------------------------------------------------

export default function SettingsPage() {
  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h2 className="text-2xl font-bold text-gray-100">Settings</h2>
        <p className="text-sm text-gray-500 mt-1">
          Manage MCP server deployment and configuration
        </p>
      </div>

      {/* Sections */}
      <div className="space-y-6">
        <McpServerSection />
        <ProxySection />
        <PasswordSection />
      </div>
    </div>
  );
}
