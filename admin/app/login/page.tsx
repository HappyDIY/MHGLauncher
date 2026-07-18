import { ShieldCheck } from "lucide-react";
import { loginAction } from "@/app/actions/auth";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const failed = Boolean((await searchParams).error);
  return <main className="flex min-h-screen items-center justify-center p-6">
    <section className="panel w-full max-w-sm p-6" aria-labelledby="login-title">
      <div className="mb-6 flex items-center gap-3"><BrandMark /><div><h1 id="login-title" className="text-lg font-semibold">云端管理面板</h1><p className="muted text-sm">站长安全登录</p></div></div>
      {failed && <p role="alert" className="mb-4 rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-700 dark:bg-red-950/30 dark:text-red-300">邮箱、密码或验证码不正确，请稍后重试。</p>}
      <form action={loginAction} className="space-y-4">
        <label className="block text-sm font-medium">邮箱<input className="input mt-1" name="email" type="email" autoComplete="username" required /></label>
        <label className="block text-sm font-medium">密码<input className="input mt-1" name="password" type="password" autoComplete="current-password" minLength={12} required /></label>
        <label className="block text-sm font-medium">验证器或恢复码<input className="input mt-1" name="code" autoComplete="one-time-code" required /></label>
        <button className="button button-primary w-full" type="submit"><ShieldCheck size={16} />登录</button>
      </form>
    </section>
  </main>;
}

function BrandMark() {
  return <span className="flex size-10 items-center justify-center rounded-md bg-[#a77b24] text-lg font-bold text-white" aria-hidden="true">M</span>;
}
