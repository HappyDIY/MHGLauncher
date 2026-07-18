import { Empty, LocalTime, PageHeader } from "@/components/common";
import { NewRelease, ReleaseOperation } from "@/components/release-actions";
import { cloudRequest } from "@/lib/cloud";
import { requireSession } from "@/lib/session";
import type { Release } from "@/lib/types";

export default async function ReleasesPage() {
  const session = await requireSession();
  const data = await cloudRequest<{ items: Release[]; environment_fallback: { version: string } | null }>("/releases", session.email);
  return <><PageHeader title="版本发布" description="管理客户端更新元数据、发布历史和回滚" action={<NewRelease csrf={session.csrf} />} />
    {data.environment_fallback && <div className="mb-4 rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-800 dark:bg-amber-950/30 dark:text-amber-200">当前 {data.environment_fallback.version} 仍来自环境变量；发布首个数据库版本后将自动切换。</div>}
    <div className="panel table-wrap"><table><thead><tr><th>版本</th><th>状态</th><th>大小</th><th>创建时间</th><th>发布时间</th><th>操作</th></tr></thead><tbody>{data.items.map((item) => <tr key={item.id}><td><p className="font-semibold">{item.version}</p><p className="muted max-w-md truncate text-xs" title={item.download_url}>{item.download_url}</p></td><td><span className="badge">{statusLabel(item.status)}</span></td><td>{formatBytes(item.size)}</td><td><LocalTime value={item.created_at} /></td><td><LocalTime value={item.published_at} /></td><td><ReleaseOperation id={item.id} version={item.version} status={item.status} csrf={session.csrf} /></td></tr>)}</tbody></table>{!data.items.length && <Empty>尚未创建版本草稿</Empty>}</div>
  </>;
}

function statusLabel(status: string) { return ({ draft: "草稿", published: "已发布", archived: "已归档" } as Record<string, string>)[status] ?? status; }
function formatBytes(value: number) { return value >= 1024 ** 3 ? `${(value / 1024 ** 3).toFixed(2)} GB` : `${(value / 1024 ** 2).toFixed(1)} MB`; }
