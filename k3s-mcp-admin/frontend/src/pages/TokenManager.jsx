import React, { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiGet, apiPost } from "../api";
import {
  KeyRound,
  RefreshCw,
  Copy,
  Check,
  RotateCw,
  Link,
  Shield,
  Clock,
} from "lucide-react";

export default function TokenManager() {
  const queryClient = useQueryClient();
  const [copiedToken, setCopiedToken] = useState(false);
  const [copiedUrl, setCopiedUrl] = useState(false);
  const [newToken, setNewToken] = useState(null);

  const { data: settings, isLoading } = useQuery({
    queryKey: ["settings"],
    queryFn: () => apiGet("/api/settings"),
  });

  const { data: health } = useQuery({
    queryKey: ["health"],
    queryFn: () => apiGet("/api/health"),
  });

  const rotateMutation = useMutation({
    mutationFn: () => apiPost("/api/settings/mcp_auth_token/rotate"),
    onSuccess: (data) => {
      setNewToken(data.token);
      queryClient.invalidateQueries({ queryKey: ["settings"] });
    },
  });

  const currentToken = settings?.mcp_auth_token || "";
  const displayToken = newToken || currentToken;
  const tunnelUrl = health?.tunnel?.url || "https://k8s-mcp.woowtech.io";
  const endpointUrl = `${tunnelUrl}/private_${displayToken}/mcp`;

  const copyToClipboard = async (text, setCopied) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // fallback
      const el = document.createElement("textarea");
      el.value = text;
      document.body.appendChild(el);
      el.select();
      document.execCommand("copy");
      document.body.removeChild(el);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <RefreshCw size={24} className="animate-spin text-gray-500" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h2 className="text-2xl font-bold text-gray-100">Token Manager</h2>
        <p className="text-sm text-gray-500 mt-1">
          Manage MCP authentication tokens
        </p>
      </div>

      {/* Current Token */}
      <div className="bg-gray-900 border border-gray-800 rounded-lg p-5 space-y-4">
        <div className="flex items-center gap-2">
          <Shield size={18} className="text-green-400" />
          <h3 className="text-lg font-semibold text-gray-200">
            MCP Auth Token
          </h3>
        </div>

        {/* Token display */}
        <div className="space-y-2">
          <label className="text-sm text-gray-400">Current Token</label>
          <div className="flex items-center gap-2">
            <code className="flex-1 px-3 py-2 bg-gray-950 border border-gray-700 rounded-lg text-sm text-green-400 font-mono truncate">
              {displayToken || "(not set)"}
            </code>
            <button
              onClick={() => copyToClipboard(displayToken, setCopiedToken)}
              disabled={!displayToken}
              className="px-3 py-2 bg-gray-800 hover:bg-gray-700 border border-gray-700 rounded-lg text-gray-300 transition-colors disabled:opacity-50"
              title="Copy token"
            >
              {copiedToken ? <Check size={16} className="text-green-400" /> : <Copy size={16} />}
            </button>
          </div>
        </div>

        {/* Endpoint URL */}
        <div className="space-y-2">
          <label className="text-sm text-gray-400 flex items-center gap-1.5">
            <Link size={14} />
            MCP Endpoint URL
          </label>
          <div className="flex items-center gap-2">
            <code className="flex-1 px-3 py-2 bg-gray-950 border border-gray-700 rounded-lg text-sm text-blue-400 font-mono truncate">
              {displayToken ? endpointUrl : "(generate token first)"}
            </code>
            <button
              onClick={() => copyToClipboard(endpointUrl, setCopiedUrl)}
              disabled={!displayToken}
              className="px-3 py-2 bg-gray-800 hover:bg-gray-700 border border-gray-700 rounded-lg text-gray-300 transition-colors disabled:opacity-50"
              title="Copy URL"
            >
              {copiedUrl ? <Check size={16} className="text-green-400" /> : <Copy size={16} />}
            </button>
          </div>
          <p className="text-xs text-gray-600">
            Use this URL in your MCP client configuration to connect to the server.
          </p>
        </div>

        {/* Rotate button */}
        <div className="pt-2 border-t border-gray-800">
          <button
            onClick={() => {
              if (
                window.confirm(
                  "Rotate token? The old token will stop working immediately."
                )
              ) {
                rotateMutation.mutate();
              }
            }}
            disabled={rotateMutation.isPending}
            className="inline-flex items-center gap-2 px-4 py-2 bg-yellow-600/20 hover:bg-yellow-600/30 border border-yellow-600/30 rounded-lg text-sm text-yellow-400 transition-colors disabled:opacity-50"
          >
            {rotateMutation.isPending ? (
              <RefreshCw size={14} className="animate-spin" />
            ) : (
              <RotateCw size={14} />
            )}
            Rotate Token
          </button>
          {rotateMutation.isSuccess && (
            <p className="text-sm text-green-400 mt-2">
              Token rotated successfully. Save it - shown only once.
            </p>
          )}
          {rotateMutation.isError && (
            <p className="text-sm text-red-400 mt-2">
              Failed to rotate: {rotateMutation.error?.message}
            </p>
          )}
        </div>
      </div>

      {/* Token History */}
      {settings?.token_history && settings.token_history.length > 0 && (
        <div className="bg-gray-900 border border-gray-800 rounded-lg p-5 space-y-3">
          <div className="flex items-center gap-2">
            <Clock size={18} className="text-gray-400" />
            <h3 className="text-lg font-semibold text-gray-200">
              Rotation History
            </h3>
          </div>
          <div className="divide-y divide-gray-800">
            {settings.token_history.map((entry, i) => (
              <div key={i} className="flex items-center justify-between py-2">
                <code className="text-sm text-gray-500 font-mono">
                  {entry.token_masked}
                </code>
                <span className="text-xs text-gray-600">
                  {new Date(entry.rotated_at).toLocaleString()}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
