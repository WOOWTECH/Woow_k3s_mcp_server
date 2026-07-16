import React from "react";
import { useQuery } from "@tanstack/react-query";
import { apiGet } from "../api";
import StatusCard from "../components/StatusCard";
import {
  RefreshCw,
  Server,
  Radio,
  Globe,
  Monitor,
  Box,
  Layers,
} from "lucide-react";

export default function Dashboard() {
  const {
    data: health,
    isLoading,
    isError,
    error,
    dataUpdatedAt,
    refetch,
  } = useQuery({
    queryKey: ["health"],
    queryFn: () => apiGet("/api/health"),
    refetchInterval: 30000,
  });

  const lastRefresh = dataUpdatedAt
    ? new Date(dataUpdatedAt).toLocaleTimeString()
    : "--";

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <RefreshCw size={24} className="animate-spin text-gray-500" />
      </div>
    );
  }

  if (isError) {
    return (
      <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-4 text-red-400">
        Failed to load health data: {error?.message || "Unknown error"}
      </div>
    );
  }

  const mcpServer = health?.mcp_server || {};
  const proxy = health?.proxy || {};
  const tunnel = health?.tunnel || {};
  const cluster = health?.cluster || {};

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-100">Dashboard</h2>
          <p className="text-sm text-gray-500 mt-1">
            System health overview
          </p>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-xs text-gray-600">
            Last refresh: {lastRefresh}
          </span>
          <button
            onClick={() => refetch()}
            className="inline-flex items-center gap-2 px-3 py-1.5 bg-gray-800 hover:bg-gray-700 border border-gray-700 rounded-lg text-sm text-gray-300 transition-colors"
          >
            <RefreshCw size={14} />
            Refresh
          </button>
        </div>
      </div>

      {/* Row 1: Service Status */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <StatusCard
          title="MCP Server"
          value={mcpServer.healthy ? "Online" : "Offline"}
          subtitle={mcpServer.pod_name || "No pod info"}
          status={mcpServer.healthy ? "green" : "red"}
          icon={Server}
        />
        <StatusCard
          title="Proxy"
          value={proxy.healthy ? "Active" : "Inactive"}
          subtitle={proxy.pod_name || "No pod info"}
          status={proxy.healthy ? "green" : "red"}
          icon={Radio}
        />
        <StatusCard
          title="Tunnel"
          value={tunnel.healthy ? "Connected" : "Unreachable"}
          subtitle={tunnel.url || "No URL configured"}
          status={tunnel.healthy ? "green" : "red"}
          icon={Monitor}
        />
      </div>

      {/* Row 2: Cluster Metrics */}
      <h3 className="text-lg font-semibold text-gray-300">Cluster Metrics</h3>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <StatusCard
          title="Nodes"
          value={cluster.nodes ?? "--"}
          status="gray"
          icon={Server}
        />
        <StatusCard
          title="Pods"
          value={cluster.pods ?? "--"}
          status="gray"
          icon={Box}
        />
        <StatusCard
          title="Namespaces"
          value={cluster.namespaces ?? "--"}
          status="gray"
          icon={Layers}
        />
      </div>
    </div>
  );
}
