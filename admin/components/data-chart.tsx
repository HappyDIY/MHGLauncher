"use client";

import { Bar, BarChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

export function DataChart({ users, gacha, achievements }: { users: number; gacha: number; achievements: number }) {
  const data = [{ name: "用户", value: users }, { name: "祈愿", value: gacha }, { name: "成就档案", value: achievements }];
  return <div className="panel h-56 p-4"><ResponsiveContainer width="100%" height="100%"><BarChart data={data} layout="vertical" margin={{ left: 4, right: 20 }}>
    <XAxis type="number" allowDecimals={false} tick={{ fill: "var(--muted)", fontSize: 12 }} axisLine={false} tickLine={false} />
    <YAxis type="category" dataKey="name" width={64} tick={{ fill: "var(--muted)", fontSize: 12 }} axisLine={false} tickLine={false} />
    <Tooltip cursor={{ fill: "color-mix(in srgb, var(--gold) 8%, transparent)" }} contentStyle={{ background: "var(--panel)", border: "1px solid var(--line)", borderRadius: 6 }} />
    <Bar dataKey="value" name="数量" fill="var(--gold)" radius={[0, 4, 4, 0]} maxBarSize={24} />
  </BarChart></ResponsiveContainer></div>;
}
