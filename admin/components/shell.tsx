"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Activity, FileClock, LogOut, Menu, Moon, PackageOpen, Shield, Sun, Users, X } from "lucide-react";
import { logoutAction } from "@/app/actions/auth";

const links = [
  { href: "/", label: "总览", icon: Activity }, { href: "/users", label: "用户", icon: Users },
  { href: "/releases", label: "版本", icon: PackageOpen }, { href: "/audit", label: "审计", icon: FileClock },
  { href: "/security", label: "安全设置", icon: Shield },
];

export function Shell({ email, children }: { email: string; children: React.ReactNode }) {
  const [open, setOpen] = useState(false), [dark, setDark] = useState(false), path = usePathname();
  useEffect(() => { const value = localStorage.theme === "dark" || (!localStorage.theme && matchMedia("(prefers-color-scheme: dark)").matches); setDark(value); document.documentElement.classList.toggle("dark", value); document.documentElement.classList.toggle("light", !value); }, []);
  function toggleTheme() { const value = !dark; setDark(value); localStorage.theme = value ? "dark" : "light"; document.documentElement.classList.toggle("dark", value); document.documentElement.classList.toggle("light", !value); }
  return <div className="min-h-screen lg:grid lg:grid-cols-[224px_1fr]">
    <header className="sticky top-0 z-30 flex h-14 items-center border-b border-[var(--line)] bg-[var(--panel)] px-4 lg:hidden">
      <button className="button size-9 p-0" onClick={() => setOpen(true)} aria-label="打开导航"><Menu size={18} /></button><span className="ml-3 font-semibold">MHGLauncher</span>
    </header>
    {open && <button className="fixed inset-0 z-30 bg-black/45 lg:hidden" onClick={() => setOpen(false)} aria-label="关闭导航遮罩" />}
    <aside className={`fixed inset-y-0 left-0 z-40 flex w-56 flex-col border-r border-[var(--line)] bg-[var(--panel)] p-3 transition-transform lg:sticky lg:top-0 lg:h-screen ${open ? "translate-x-0" : "-translate-x-full lg:translate-x-0"}`}>
      <div className="mb-5 flex h-11 items-center gap-3 px-2"><span className="flex size-9 items-center justify-center rounded-md bg-[#a77b24] font-bold text-white">M</span><div><p className="font-semibold">MHGLauncher</p><p className="muted text-xs">云端管理</p></div><button className="ml-auto lg:hidden" onClick={() => setOpen(false)} aria-label="关闭导航"><X size={18} /></button></div>
      <nav className="space-y-1">{links.map(({ href, label, icon: Icon }) => <Link key={href} href={href} onClick={() => setOpen(false)} className={`flex h-10 items-center gap-3 rounded-md px-3 text-sm font-medium ${path === href ? "bg-[#a77b24]/12 text-[var(--gold)]" : "muted hover:bg-black/5 dark:hover:bg-white/5"}`}><Icon size={17} />{label}</Link>)}</nav>
      <div className="mt-auto border-t border-[var(--line)] pt-3"><p className="truncate px-2 pb-2 text-xs muted">{email}</p><div className="flex gap-2"><button className="button size-9 p-0" onClick={toggleTheme} title="切换主题" aria-label="切换主题">{dark ? <Sun size={16} /> : <Moon size={16} />}</button><form action={logoutAction} className="flex-1"><button className="button w-full" type="submit"><LogOut size={16} />退出</button></form></div></div>
    </aside>
    <main className="min-w-0 p-4 sm:p-6 lg:p-8">{children}</main>
  </div>;
}
