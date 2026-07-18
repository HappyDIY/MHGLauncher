import Link from "next/link";
import { Search } from "lucide-react";
import { Empty, LocalTime, PageHeader } from "@/components/common";
import { UserActions } from "@/components/user-actions";
import { cloudRequest } from "@/lib/cloud";
import { requireSession } from "@/lib/session";
import type { CloudUser } from "@/lib/types";

export default async function UsersPage({ searchParams }: { searchParams: Promise<{ query?: string; cursor?: string }> }) {
  const session = await requireSession(), params = await searchParams;
  const query = /^\d{0,10}$/.test(params.query ?? "") ? params.query ?? "" : "";
  const cursor = /^\d{9,10}$/.test(params.cursor ?? "") ? params.cursor : undefined;
  const search = new URLSearchParams({ query }); if (cursor) search.set("cursor", cursor);
  const data = await cloudRequest<{ items: CloudUser[]; next_cursor: string | null }>(`/users?${search}`, session.email);
  return <>
    <PageHeader title="用户" description="查询云同步账号并执行会话或数据操作" action={<SearchForm query={query} />} />
    <div className="panel table-wrap"><table><thead><tr><th>UID</th><th>创建时间</th><th>活跃会话</th><th>祈愿</th><th>成就</th><th>最近数据</th><th className="text-right">操作</th></tr></thead>
      <tbody>{data.items.map((user) => <tr key={user.uid}>
        <td className="font-mono font-semibold">{user.uid}</td><td><LocalTime value={user.created_at} /></td>
        <td>{user.active_sessions}</td><td>{user.gacha_count.toLocaleString("zh-CN")}</td><td>{user.achievement_count.toLocaleString("zh-CN")}</td>
        <td><LocalTime value={user.latest_gacha ?? user.achievement_updated_at} /></td>
        <td><UserActions uid={user.uid} csrf={session.csrf} counts={{ sessions: user.total_sessions, gacha: user.gacha_count, achievements: user.achievement_count }} /></td>
      </tr>)}</tbody></table>{!data.items.length && <Empty>没有匹配的用户</Empty>}</div>
    {data.next_cursor && <div className="mt-4 flex justify-end"><Link className="button" href={`/users?query=${query}&cursor=${data.next_cursor}`}>下一页</Link></div>}
  </>;
}

function SearchForm({ query }: { query: string }) {
  return <form className="flex gap-2"><div className="relative"><Search className="muted absolute left-2.5 top-2.5" size={16} /><input className="input w-56 pl-8" name="query" defaultValue={query} placeholder="按 UID 前缀搜索" inputMode="numeric" /></div><button className="button" type="submit">搜索</button></form>;
}
