import React from "react";

const statusColors = {
  green: {
    dot: "bg-green-500",
    glow: "shadow-[0_0_8px_rgba(34,197,94,0.6)]",
    ring: "ring-green-500/30",
  },
  yellow: {
    dot: "bg-yellow-500",
    glow: "shadow-[0_0_8px_rgba(234,179,8,0.6)]",
    ring: "ring-yellow-500/30",
  },
  red: {
    dot: "bg-red-500",
    glow: "shadow-[0_0_8px_rgba(239,68,68,0.6)]",
    ring: "ring-red-500/30",
  },
  gray: {
    dot: "bg-gray-500",
    glow: "",
    ring: "ring-gray-500/30",
  },
};

export default function StatusCard({
  title,
  value,
  subtitle,
  status = "gray",
  icon: Icon,
}) {
  const colors = statusColors[status] || statusColors.gray;

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-lg p-5">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-medium text-gray-400">{title}</h3>
        <div className="flex items-center gap-2">
          {Icon && <Icon size={16} className="text-gray-500" />}
          <span
            className={`inline-block w-2.5 h-2.5 rounded-full ${colors.dot} ${colors.glow} ring-2 ${colors.ring}`}
          />
        </div>
      </div>
      <p className="text-2xl font-semibold text-gray-100">{value}</p>
      {subtitle && (
        <p className="text-xs text-gray-500 mt-1 truncate" title={subtitle}>
          {subtitle}
        </p>
      )}
    </div>
  );
}
