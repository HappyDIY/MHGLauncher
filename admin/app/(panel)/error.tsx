"use client";

import { AlertTriangle, RotateCw } from "lucide-react";

export default function ErrorPage({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <div className="panel mx-auto mt-20 max-w-lg p-8 text-center"><AlertTriangle className="mx-auto mb-3 text-amber-500" size={28} /><h1 className="text-lg font-semibold">暂时无法读取管理数据</h1><p className="muted my-3 text-sm">请检查 cloud 服务和数据库状态后重试。</p><button className="button" onClick={reset}><RotateCw size={16} />重试</button></div>;
}
