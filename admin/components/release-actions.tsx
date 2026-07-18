"use client";

import * as Dialog from "@radix-ui/react-dialog";
import * as AlertDialog from "@radix-ui/react-alert-dialog";
import { Plus, RotateCcw, Rocket, X } from "lucide-react";
import { createReleaseAction, publishReleaseAction } from "@/app/actions/cloud";

export function NewRelease({ csrf }: { csrf: string }) {
  return <Dialog.Root><Dialog.Trigger asChild><button className="button button-primary"><Plus size={16} />新建草稿</button></Dialog.Trigger><Dialog.Portal><Dialog.Overlay className="dialog-overlay" /><Dialog.Content className="dialog panel">
    <div className="mb-4 flex items-center justify-between"><Dialog.Title className="text-lg font-semibold">新建版本草稿</Dialog.Title><Dialog.Close aria-label="关闭"><X size={18} /></Dialog.Close></div>
    <form action={createReleaseAction} className="space-y-3"><input type="hidden" name="csrf" value={csrf} />
      <Field name="version" label="版本号" placeholder="1.2.0" /><Field name="download_url" label="下载地址" placeholder="https://…/MHGLauncher.dmg" />
      <Field name="sha256" label="SHA-256" placeholder="64 位十六进制摘要" /><Field name="size" label="文件大小（字节）" type="number" placeholder="1024" />
      <label className="block text-sm">更新日志<textarea className="input mt-1 min-h-28 resize-y" name="changelog" maxLength={20000} required /></label>
      <button className="button button-primary w-full" type="submit">保存草稿</button>
    </form>
  </Dialog.Content></Dialog.Portal></Dialog.Root>;
}

export function ReleaseOperation({ id, version, status, csrf }: { id: number; version: string; status: string; csrf: string }) {
  if (status === "published") return <span className="badge text-emerald-600">当前版本</span>;
  const rollback = status === "archived", label = rollback ? "回滚" : "发布", Icon = rollback ? RotateCcw : Rocket;
  return <AlertDialog.Root><AlertDialog.Trigger asChild><button className="button"><Icon size={15} />{label}</button></AlertDialog.Trigger><AlertDialog.Portal><AlertDialog.Overlay className="dialog-overlay" /><AlertDialog.Content className="dialog panel">
    <AlertDialog.Title className="text-lg font-semibold">{label} {version}？</AlertDialog.Title><AlertDialog.Description className="muted my-3 text-sm">当前发布版本将自动归档，客户端随后会读取这个版本。</AlertDialog.Description>
    <form action={publishReleaseAction}><input type="hidden" name="csrf" value={csrf} /><input type="hidden" name="id" value={id} /><input type="hidden" name="operation" value={rollback ? "rollback" : "publish"} /><button className="button button-primary w-full" type="submit">确认{label}</button></form>
    <AlertDialog.Cancel asChild><button className="button mt-3 w-full">取消</button></AlertDialog.Cancel>
  </AlertDialog.Content></AlertDialog.Portal></AlertDialog.Root>;
}

function Field({ name, label, placeholder, type = "text" }: { name: string; label: string; placeholder: string; type?: string }) {
  return <label className="block text-sm">{label}<input className="input mt-1" name={name} type={type} placeholder={placeholder} required /></label>;
}
