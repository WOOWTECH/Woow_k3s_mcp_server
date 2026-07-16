import React, { useState, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiGet } from "../api";
import { RefreshCw, Server, Layers, Box } from "lucide-react";

const TABS = [
  { id: "nodes", label: "Nodes", icon: Server },
  { id: "namespaces", label: "Namespaces", icon: Layers },
  { id: "pods", label: "Pods", icon: Box },
];

function TableHeader({ children }) {
  return (
    <th className="px-4 py-2.5 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
      {children}
    </th>
  );
}

function TableCell({ children, className = "" }) {
  return (
    <td className={`px-4 py-2.5 text-sm text-gray-300 ${className}`}>
      {children}
    </td>
  );
}

function StatusBadge({ status }) {
  const isActive =
    status === "Ready" || status === "Active" || status === "Running";
  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs ${
        isActive
          ? "bg-green-500/10 text-green-400"
          : "bg-red-500/10 text-red-400"
      }`}
    >
      <span
        className={`w-1.5 h-1.5 rounded-full ${
          isActive ? "bg-green-500" : "bg-red-500"
        }`}
      />
      {status}
    </span>
  );
}

function LoadingState() {
  return (
    <div className="flex items-center justify-center h-48">
      <RefreshCw size={24} className="animate-spin text-gray-500" />
    </div>
  );
}

function ErrorState({ message }) {
  return (
    <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-4 text-red-400 text-sm">
      {message}
    </div>
  );
}

function EmptyState({ message }) {
  return (
    <div className="text-center py-12 text-gray-600 text-sm">{message}</div>
  );
}

// -----------------------------------------------------------------------
// Nodes Tab
// -----------------------------------------------------------------------

function NodesTab() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["cluster-nodes"],
    queryFn: () => apiGet("/api/cluster/nodes"),
    refetchInterval: 30000,
  });

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message={error?.message || "Failed to load nodes"} />;

  const nodes = data?.nodes || data || [];
  if (nodes.length === 0) return <EmptyState message="No nodes found" />;

  return (
    <div className="overflow-x-auto">
      <table className="w-full">
        <thead className="bg-gray-800/50">
          <tr>
            <TableHeader>Name</TableHeader>
            <TableHeader>Status</TableHeader>
            <TableHeader>Roles</TableHeader>
            <TableHeader>Age</TableHeader>
            <TableHeader>CPU (allocatable)</TableHeader>
            <TableHeader>Memory (allocatable)</TableHeader>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-800/50">
          {nodes.map((node, i) => (
            <tr key={node.name || i} className="hover:bg-gray-800/30 transition-colors">
              <TableCell className="font-mono text-green-400">
                {node.name}
              </TableCell>
              <TableCell>
                <StatusBadge status={node.status || "Unknown"} />
              </TableCell>
              <TableCell>{node.roles || "--"}</TableCell>
              <TableCell>{node.age || "--"}</TableCell>
              <TableCell>{node.cpu_allocatable || node.cpu || "--"}</TableCell>
              <TableCell>{node.memory_allocatable || node.memory || "--"}</TableCell>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// -----------------------------------------------------------------------
// Namespaces Tab
// -----------------------------------------------------------------------

function NamespacesTab() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["cluster-namespaces"],
    queryFn: () => apiGet("/api/cluster/namespaces"),
    refetchInterval: 30000,
  });

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message={error?.message || "Failed to load namespaces"} />;

  const namespaces = data?.namespaces || data || [];
  if (namespaces.length === 0) return <EmptyState message="No namespaces found" />;

  return (
    <div className="overflow-x-auto">
      <table className="w-full">
        <thead className="bg-gray-800/50">
          <tr>
            <TableHeader>Name</TableHeader>
            <TableHeader>Status</TableHeader>
            <TableHeader>Age</TableHeader>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-800/50">
          {namespaces.map((ns, i) => (
            <tr key={ns.name || i} className="hover:bg-gray-800/30 transition-colors">
              <TableCell className="font-mono text-green-400">
                {ns.name}
              </TableCell>
              <TableCell>
                <StatusBadge status={ns.status || "Active"} />
              </TableCell>
              <TableCell>{ns.age || "--"}</TableCell>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// -----------------------------------------------------------------------
// Pods Tab
// -----------------------------------------------------------------------

function PodsTab() {
  const [selectedNamespace, setSelectedNamespace] = useState("");

  const { data: nsData } = useQuery({
    queryKey: ["cluster-namespaces"],
    queryFn: () => apiGet("/api/cluster/namespaces"),
    refetchInterval: 30000,
  });

  const namespaces = nsData?.namespaces || nsData || [];

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["cluster-pods", selectedNamespace],
    queryFn: () =>
      apiGet(
        selectedNamespace
          ? `/api/cluster/pods?namespace=${selectedNamespace}`
          : "/api/cluster/pods"
      ),
    refetchInterval: 30000,
  });

  const pods = data?.pods || data || [];

  return (
    <div className="space-y-4">
      {/* Namespace filter */}
      <div className="flex items-center gap-3">
        <label className="text-sm text-gray-400">Namespace:</label>
        <select
          value={selectedNamespace}
          onChange={(e) => setSelectedNamespace(e.target.value)}
          className="px-3 py-1.5 bg-gray-900 border border-gray-700 rounded-lg text-sm text-gray-200 focus:outline-none focus:ring-2 focus:ring-green-500/50"
        >
          <option value="">All namespaces</option>
          {namespaces.map((ns, i) => (
            <option key={ns.name || i} value={ns.name}>
              {ns.name}
            </option>
          ))}
        </select>
      </div>

      {isLoading ? (
        <LoadingState />
      ) : isError ? (
        <ErrorState message={error?.message || "Failed to load pods"} />
      ) : pods.length === 0 ? (
        <EmptyState message="No pods found" />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-800/50">
              <tr>
                <TableHeader>Name</TableHeader>
                <TableHeader>Namespace</TableHeader>
                <TableHeader>Status</TableHeader>
                <TableHeader>Ready</TableHeader>
                <TableHeader>Restarts</TableHeader>
                <TableHeader>Age</TableHeader>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-800/50">
              {pods.map((pod, i) => {
                const isRunning =
                  pod.phase === "Running" || pod.status === "Running";
                return (
                  <tr
                    key={pod.name || i}
                    className="hover:bg-gray-800/30 transition-colors"
                  >
                    <TableCell className="font-mono text-green-400 max-w-xs truncate">
                      {pod.name}
                    </TableCell>
                    <TableCell>{pod.namespace || "--"}</TableCell>
                    <TableCell>
                      <StatusBadge
                        status={pod.phase || pod.status || "Unknown"}
                      />
                    </TableCell>
                    <TableCell>{pod.ready_str || (pod.ready ? "Yes" : "No")}</TableCell>
                    <TableCell>
                      <span
                        className={
                          (pod.restart_count || 0) > 0
                            ? "text-yellow-400"
                            : ""
                        }
                      >
                        {pod.restart_count ?? pod.restarts ?? 0}
                      </span>
                    </TableCell>
                    <TableCell>{pod.age || "--"}</TableCell>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

// -----------------------------------------------------------------------
// Main Component
// -----------------------------------------------------------------------

export default function ClusterOverview() {
  const [activeTab, setActiveTab] = useState("nodes");

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h2 className="text-2xl font-bold text-gray-100">Cluster Overview</h2>
        <p className="text-sm text-gray-500 mt-1">
          K3s cluster resources and status
        </p>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 border-b border-gray-800">
        {TABS.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => setActiveTab(id)}
            className={`inline-flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 transition-colors ${
              activeTab === id
                ? "border-green-500 text-green-400"
                : "border-transparent text-gray-500 hover:text-gray-300 hover:border-gray-700"
            }`}
          >
            <Icon size={16} />
            {label}
          </button>
        ))}
      </div>

      {/* Tab Content */}
      <div className="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden">
        {activeTab === "nodes" && <NodesTab />}
        {activeTab === "namespaces" && <NamespacesTab />}
        {activeTab === "pods" && <PodsTab />}
      </div>
    </div>
  );
}
