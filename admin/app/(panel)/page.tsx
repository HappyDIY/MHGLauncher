import { Activity, Archive, Database, PackageCheck, ScrollText, Users } from "lucide-react";
import { LocalTime, PageHeader } from "@/components/common";
import { cloudRequest } from "@/lib/cloud";
import { requireSession } from "@/lib/session";
import type { Overview } from "@/lib/types";
import { DataChart } from "@/components/data-chart";

export default async function OverviewPage() {
  const session = await requireSession(), data = await cloudRequest<Overview>("/overview", session.email);
  const stats = [
    ["用户", data.totals.users, Users], ["活跃会话", data.totals.active_sessions, Activity],
    ["祈愿记录", data.totals.gacha_records, ScrollText], ["成就档案", data.totals.achievement_archives, Archive],
  ] as const;
  return <><PageHeader title="运行总览" description="云端服务、用户数据和发布状态" />
    <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">{stats.map(([label, value, Icon]) => <div className="panel p-4" key={label}><div className="mb-3 flex items-center justify-between"><span className="muted text-sm">{label}</span><Icon size={17} className="text-[var(--gold)]" /></div><strong className="text-2xl font-semibold tabular-nums">{value.toLocaleString("zh-CN")}</strong></div>)}</section>
    <section className="mt-6 grid gap-6 xl:grid-cols-[1fr_1.4fr]"><div><h2 className="mb-3 text-base font-semibold">服务状态</h2><div className="panel divide-y divide-[var(--line)]"><Status icon={<Database size={17} />} label="PostgreSQL" value={data.database === "connected" ? "已连接" : "异常"} /><Status icon={<Activity size={17} />} label="Cloud API" value={data.healthy ? "运行正常" : "异常"} /><Status icon={<PackageCheck size={17} />} label="当前版本" value={data.current_release?.version ?? "未配置"} detail={data.current_release?.source === "environment" ? "环境变量来源" : "数据库发布"} /></div><h2 className="mb-3 mt-6 text-base font-semibold">数据规模</h2><DataChart users={data.totals.users} gacha={data.totals.gacha_records} achievements={data.totals.achievement_archives} /></div>
      <div><h2 className="mb-3 text-base font-semibold">最近管理操作</h2><div className="panel table-wrap"><table><thead><tr><th>操作</th><th>目标</th><th>时间</th></tr></thead><tbody>{data.recent_audit.map((event) => <tr key={event.id}><td>{event.action}</td><td className="muted">{event.target_ref}</td><td><LocalTime value={event.created_at} /></td></tr>)}{!data.recent_audit.length && <tr><td colSpan={3} className="text-center muted">暂无管理操作</td></tr>}</tbody></table></div></div></section>
  </>;
}

function Status({ icon, label, value, detail }: { icon: React.ReactNode; label: string; value: string; detail?: string }) {
  return <div className="flex items-center gap-3 p-4"><span className="text-[var(--gold)]">{icon}</span><span className="text-sm font-medium">{label}</span><span className="ml-auto text-sm text-emerald-600">{value}</span>{detail && <span className="badge">{detail}</span>}</div>;
}
