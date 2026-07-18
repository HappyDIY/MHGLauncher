import { KeyRound, LockKeyhole, ShieldCheck, Smartphone } from "lucide-react";
import { revokeOtherSessionsAction } from "@/app/actions/auth";
import { LocalTime, PageHeader } from "@/components/common";
import { pool, ready } from "@/lib/db";
import { requireSession } from "@/lib/session";

export default async function SecurityPage() {
  const session = await requireSession(); await ready();
  const [sessions, codes, audits] = await Promise.all([
    pool().query("SELECT COUNT(*) count FROM admin.admin_sessions WHERE revoked_at IS NULL AND expires_at>now()"),
    pool().query("SELECT COUNT(*) count FROM admin.recovery_codes WHERE used_at IS NULL"),
    pool().query("SELECT id,action,result,created_at FROM admin.auth_audit_events ORDER BY id DESC LIMIT 8"),
  ]);
  return <><PageHeader title="安全设置" description="站长认证状态与登录会话" />
    <section className="grid gap-3 sm:grid-cols-3"><SecurityStat icon={<LockKeyhole size={18} />} label="密码保护" value="Argon2id" /><SecurityStat icon={<Smartphone size={18} />} label="双重验证" value="已启用" /><SecurityStat icon={<KeyRound size={18} />} label="可用恢复码" value={String(codes.rows[0].count)} /></section>
    <section className="mt-6 grid gap-6 xl:grid-cols-2"><div><h2 className="mb-3 font-semibold">登录会话</h2><div className="panel p-4"><div className="flex items-center gap-3"><ShieldCheck className="text-[var(--gold)]" size={20} /><div><p className="font-medium">{sessions.rows[0].count} 个有效会话</p><p className="muted text-sm">当前会话保持登录，其他会话可以立即撤销。</p></div></div><form action={revokeOtherSessionsAction} className="mt-4"><input type="hidden" name="csrf" value={session.csrf} /><button className="button" type="submit">撤销其他会话</button></form></div></div>
      <div><h2 className="mb-3 font-semibold">最近登录事件</h2><div className="panel table-wrap"><table><thead><tr><th>时间</th><th>动作</th><th>结果</th></tr></thead><tbody>{audits.rows.map((event) => <tr key={event.id}><td><LocalTime value={event.created_at.toISOString()} /></td><td>{event.action}</td><td>{event.result === "success" ? "成功" : "失败"}</td></tr>)}</tbody></table></div></div></section>
    <p className="muted mt-6 text-sm">重置密码、TOTP 或恢复码请在服务器运行 <code>npm run owner:create -- --reset</code>。</p>
  </>;
}

function SecurityStat({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return <div className="panel flex items-center gap-3 p-4"><span className="text-[var(--gold)]">{icon}</span><div><p className="muted text-xs">{label}</p><p className="font-semibold">{value}</p></div></div>;
}
