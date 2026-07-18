import Link from "next/link";
import { Empty, LocalTime, PageHeader } from "@/components/common";
import { cloudRequest } from "@/lib/cloud";
import { requireSession } from "@/lib/session";
import type { AuditEvent } from "@/lib/types";

export default async function AuditPage({ searchParams }: { searchParams: Promise<{ cursor?: string }> }) {
  const session = await requireSession(), params = await searchParams;
  const cursor = /^\d+$/.test(params.cursor ?? "") ? params.cursor : undefined;
  const data = await cloudRequest<{ items: AuditEvent[]; next_cursor: number | null }>(`/audit${cursor ? `?cursor=${cursor}` : ""}`, session.email);
  return <><PageHeader title="审计日志" description="不可修改的云端管理操作记录" />
    <div className="panel table-wrap"><table><thead><tr><th>时间</th><th>站长</th><th>操作</th><th>目标类型</th><th>目标</th><th>结果</th></tr></thead><tbody>{data.items.map((event) => <tr key={event.id}><td><LocalTime value={event.created_at} /></td><td>{event.actor}</td><td className="font-mono text-xs">{event.action}</td><td>{event.target_type}</td><td className="font-mono text-xs">{event.target_ref}</td><td><span className="badge text-emerald-600">成功</span></td></tr>)}</tbody></table>{!data.items.length && <Empty>暂无审计事件</Empty>}</div>
    {data.next_cursor && <div className="mt-4 flex justify-end"><Link className="button" href={`/audit?cursor=${data.next_cursor}`}>下一页</Link></div>}
  </>;
}
