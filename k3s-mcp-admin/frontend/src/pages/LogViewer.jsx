import React, { useState, useEffect, useRef, useCallback } from "react";
import { createEventSource } from "../api";
import {
  ScrollText,
  Pause,
  Play,
  Trash2,
  Search,
  Wifi,
  WifiOff,
  ArrowDown,
} from "lucide-react";

export default function LogViewer() {
  const [logs, setLogs] = useState([]);
  const [connected, setConnected] = useState(false);
  const [paused, setPaused] = useState(false);
  const [filter, setFilter] = useState("");
  const [autoScroll, setAutoScroll] = useState(true);
  const logsEndRef = useRef(null);
  const eventSourceRef = useRef(null);
  const pausedRef = useRef(false);

  // Keep ref in sync
  useEffect(() => {
    pausedRef.current = paused;
  }, [paused]);

  // Auto-scroll
  useEffect(() => {
    if (autoScroll && !paused && logsEndRef.current) {
      logsEndRef.current.scrollIntoView({ behavior: "smooth" });
    }
  }, [logs, autoScroll, paused]);

  // SSE connection
  useEffect(() => {
    const es = createEventSource("/api/logs/stream");
    eventSourceRef.current = es;

    es.onopen = () => setConnected(true);

    es.onmessage = (event) => {
      if (pausedRef.current) return;

      try {
        const data = JSON.parse(event.data);
        setLogs((prev) => {
          const next = [
            ...prev,
            {
              id: Date.now() + Math.random(),
              timestamp: data.timestamp || new Date().toISOString(),
              level: data.level || "info",
              message: data.message || data.line || event.data,
              source: data.pod_name || data.source || "",
            },
          ];
          // Keep max 2000 lines
          return next.length > 2000 ? next.slice(-2000) : next;
        });
      } catch {
        // Plain text line
        setLogs((prev) => {
          const next = [
            ...prev,
            {
              id: Date.now() + Math.random(),
              timestamp: new Date().toISOString(),
              level: "info",
              message: event.data,
              source: "",
            },
          ];
          return next.length > 2000 ? next.slice(-2000) : next;
        });
      }
    };

    es.onerror = () => {
      setConnected(false);
    };

    return () => {
      es.close();
      eventSourceRef.current = null;
    };
  }, []);

  const filteredLogs = filter
    ? logs.filter(
        (log) =>
          log.message.toLowerCase().includes(filter.toLowerCase()) ||
          log.source.toLowerCase().includes(filter.toLowerCase())
      )
    : logs;

  const levelColor = (level) => {
    switch (level?.toLowerCase()) {
      case "error":
        return "text-red-400";
      case "warn":
      case "warning":
        return "text-yellow-400";
      case "debug":
        return "text-gray-500";
      default:
        return "text-gray-400";
    }
  };

  return (
    <div className="space-y-4 flex flex-col h-[calc(100vh-5rem)]">
      {/* Header */}
      <div className="flex items-center justify-between flex-shrink-0">
        <div className="flex items-center gap-3">
          <h2 className="text-2xl font-bold text-gray-100">Logs</h2>
          <span
            className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs ${
              connected
                ? "bg-green-500/10 text-green-400"
                : "bg-red-500/10 text-red-400"
            }`}
          >
            {connected ? (
              <>
                <Wifi size={12} /> Connected
              </>
            ) : (
              <>
                <WifiOff size={12} /> Disconnected
              </>
            )}
          </span>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setPaused((p) => !p)}
            className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm border transition-colors ${
              paused
                ? "bg-yellow-500/10 border-yellow-500/30 text-yellow-400"
                : "bg-gray-800 border-gray-700 text-gray-300 hover:bg-gray-700"
            }`}
          >
            {paused ? <Play size={14} /> : <Pause size={14} />}
            {paused ? "Resume" : "Pause"}
          </button>
          <button
            onClick={() => setAutoScroll((a) => !a)}
            className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm border transition-colors ${
              autoScroll
                ? "bg-green-500/10 border-green-500/30 text-green-400"
                : "bg-gray-800 border-gray-700 text-gray-300 hover:bg-gray-700"
            }`}
          >
            <ArrowDown size={14} />
            Auto-scroll
          </button>
          <button
            onClick={() => setLogs([])}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-gray-800 hover:bg-gray-700 border border-gray-700 rounded-lg text-sm text-gray-300 transition-colors"
          >
            <Trash2 size={14} />
            Clear
          </button>
        </div>
      </div>

      {/* Filter */}
      <div className="relative flex-shrink-0">
        <Search
          size={16}
          className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500"
        />
        <input
          type="text"
          placeholder="Filter logs..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="w-full pl-9 pr-4 py-2 bg-gray-900 border border-gray-700 rounded-lg text-gray-100 placeholder-gray-600 focus:outline-none focus:ring-2 focus:ring-green-500/50 focus:border-green-500/50 text-sm"
        />
      </div>

      {/* Log output */}
      <div className="flex-1 bg-gray-950 border border-gray-800 rounded-lg overflow-auto font-mono text-xs p-3 min-h-0">
        {filteredLogs.length === 0 ? (
          <div className="flex items-center justify-center h-full text-gray-600">
            <ScrollText size={20} className="mr-2" />
            {connected ? "Waiting for log entries..." : "Connecting..."}
          </div>
        ) : (
          <div className="space-y-0.5">
            {filteredLogs.map((log) => (
              <div key={log.id} className="flex gap-2 leading-5 hover:bg-gray-900/50">
                <span className="text-gray-600 whitespace-nowrap flex-shrink-0">
                  {new Date(log.timestamp).toLocaleTimeString()}
                </span>
                {log.source && (
                  <span className="text-blue-400 whitespace-nowrap flex-shrink-0">
                    [{log.source}]
                  </span>
                )}
                <span className={`${levelColor(log.level)} whitespace-nowrap flex-shrink-0 uppercase w-12`}>
                  {log.level}
                </span>
                <span className="text-gray-300 break-all">{log.message}</span>
              </div>
            ))}
            <div ref={logsEndRef} />
          </div>
        )}
      </div>

      {/* Status bar */}
      <div className="flex items-center justify-between text-xs text-gray-600 flex-shrink-0">
        <span>{filteredLogs.length} entries</span>
        {paused && <span className="text-yellow-400">Paused</span>}
      </div>
    </div>
  );
}
