import React, { useState, useMemo } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiGet, apiPut } from "../api";
import {
  Search,
  Wrench,
  AlertTriangle,
  RefreshCw,
  ChevronDown,
  ChevronRight,
} from "lucide-react";

const CATEGORIES = {
  Core: [
    "pods_list", "pods_get", "pods_run", "pods_delete", "pods_log",
    "pods_exec", "pods_top", "pods_list_in_namespace",
    "resources_list", "resources_get", "resources_create_or_update",
    "resources_delete", "resources_scale",
    "namespaces_list", "nodes_top", "nodes_log", "nodes_stats_summary",
    "events_list", "configuration_view",
  ],
  Config: [
    "pods_run", "resources_create_or_update", "resources_delete",
    "resources_scale",
  ],
  Helm: [
    "helm_install", "helm_list", "helm_uninstall",
  ],
};

const DANGEROUS_TOOLS = new Set([
  "pods_delete",
  "pods_exec",
  "resources_delete",
  "helm_uninstall",
]);

export default function ToolManager() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [expandedCategories, setExpandedCategories] = useState(
    new Set(Object.keys(CATEGORIES))
  );

  const { data: settings, isLoading } = useQuery({
    queryKey: ["settings"],
    queryFn: () => apiGet("/api/settings"),
  });

  const toggleMutation = useMutation({
    mutationFn: async ({ toolName, disabled }) => {
      const current = settings?.tools?.disabled || [];
      const updated = disabled
        ? [...new Set([...current, toolName])]
        : current.filter((t) => t !== toolName);
      return apiPut("/api/settings/tools", { disabled: updated, disabled_operations: settings?.tools?.disabled_operations || {} });
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["settings"] }),
  });

  const disabledSet = useMemo(
    () => new Set(settings?.tools?.disabled || []),
    [settings]
  );

  const toggleCategory = (cat) => {
    setExpandedCategories((prev) => {
      const next = new Set(prev);
      if (next.has(cat)) next.delete(cat);
      else next.add(cat);
      return next;
    });
  };

  // Build deduplicated tool list per category
  const categorizedTools = useMemo(() => {
    const result = {};
    const seen = new Set();

    for (const [category, tools] of Object.entries(CATEGORIES)) {
      const filtered = tools
        .filter((t) => !seen.has(t))
        .filter(
          (t) =>
            !search ||
            t.toLowerCase().includes(search.toLowerCase())
        );
      filtered.forEach((t) => seen.add(t));
      if (filtered.length > 0) {
        result[category] = filtered;
      }
    }
    return result;
  }, [search]);

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
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-100">Tool Manager</h2>
          <p className="text-sm text-gray-500 mt-1">
            Enable or disable MCP tools
          </p>
        </div>
      </div>

      {/* Search */}
      <div className="relative">
        <Search
          size={16}
          className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500"
        />
        <input
          type="text"
          placeholder="Search tools..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full pl-9 pr-4 py-2 bg-gray-900 border border-gray-700 rounded-lg text-gray-100 placeholder-gray-600 focus:outline-none focus:ring-2 focus:ring-green-500/50 focus:border-green-500/50 text-sm"
        />
      </div>

      {/* Categories */}
      <div className="space-y-3">
        {Object.entries(categorizedTools).map(([category, tools]) => (
          <div
            key={category}
            className="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden"
          >
            {/* Category header */}
            <button
              onClick={() => toggleCategory(category)}
              className="w-full flex items-center justify-between px-4 py-3 hover:bg-gray-800/50 transition-colors"
            >
              <div className="flex items-center gap-2">
                {expandedCategories.has(category) ? (
                  <ChevronDown size={16} className="text-gray-500" />
                ) : (
                  <ChevronRight size={16} className="text-gray-500" />
                )}
                <span className="font-medium text-gray-200">{category}</span>
                <span className="text-xs text-gray-600">
                  ({tools.length} tools)
                </span>
              </div>
            </button>

            {/* Tool list */}
            {expandedCategories.has(category) && (
              <div className="border-t border-gray-800 divide-y divide-gray-800/50">
                {tools.map((tool) => {
                  const isDangerous = DANGEROUS_TOOLS.has(tool);
                  const isDisabled = disabledSet.has(tool);

                  return (
                    <div
                      key={tool}
                      className="flex items-center justify-between px-4 py-2.5 hover:bg-gray-800/30 transition-colors"
                    >
                      <div className="flex items-center gap-3">
                        <Wrench size={14} className="text-gray-600" />
                        <span
                          className={`text-sm font-mono ${
                            isDisabled ? "text-gray-600 line-through" : "text-gray-300"
                          }`}
                        >
                          {tool}
                        </span>
                        {isDangerous && (
                          <span className="inline-flex items-center gap-1 px-1.5 py-0.5 bg-red-500/10 border border-red-500/20 rounded text-xs text-red-400">
                            <span className="w-1.5 h-1.5 rounded-full bg-red-500 inline-block" />
                            dangerous
                          </span>
                        )}
                      </div>

                      <button
                        onClick={() =>
                          toggleMutation.mutate({
                            toolName: tool,
                            disabled: !isDisabled,
                          })
                        }
                        disabled={toggleMutation.isPending}
                        className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${
                          isDisabled
                            ? "bg-gray-700"
                            : "bg-green-600"
                        }`}
                      >
                        <span
                          className={`inline-block h-3.5 w-3.5 transform rounded-full bg-white transition-transform ${
                            isDisabled
                              ? "translate-x-0.5"
                              : "translate-x-[18px]"
                          }`}
                        />
                      </button>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
