"use client";

import { useEffect, useState } from "react";

export function LocalTime({ value }: { value: string | null }) {
  const [text, setText] = useState(value ? "…" : "—");
  useEffect(() => { if (value) setText(new Intl.DateTimeFormat("zh-CN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value))); }, [value]);
  return <time dateTime={value ?? undefined}>{text}</time>;
}

export function PageHeader({ title, description, action }: { title: string; description: string; action?: React.ReactNode }) {
  return <header className="mb-6 flex flex-wrap items-end justify-between gap-3"><div><h1 className="text-2xl font-semibold">{title}</h1><p className="muted mt-1 text-sm">{description}</p></div>{action}</header>;
}

export function Empty({ children }: { children: React.ReactNode }) {
  return <div className="p-10 text-center text-sm muted">{children}</div>;
}
