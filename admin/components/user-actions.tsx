"use client";

import * as AlertDialog from "@radix-ui/react-alert-dialog";
import { KeyRound, Trash2 } from "lucide-react";
import { deleteUserAction, revokeSessionsAction } from "@/app/actions/cloud";

export function UserActions({ uid, csrf, counts }: { uid: string; csrf: string; counts: { sessions: number; gacha: number; achievements: number } }) {
  return <div className="flex justify-end gap-2">
    <Confirm title="撤销该用户的全部会话？" description="用户需要重新验证抽卡 URL 后才能继续使用云同步。" trigger={<button className="button size-9 p-0" title="撤销会话" aria-label={`撤销 ${uid} 的会话`}><KeyRound size={15} /></button>}>
      <form action={revokeSessionsAction}><input type="hidden" name="csrf" value={csrf} /><input type="hidden" name="uid" value={uid} /><Submit>确认撤销</Submit></form>
    </Confirm>
    <Confirm title={`永久删除用户 ${uid}？`} description={`将删除 ${counts.sessions} 个会话、${counts.gacha} 条祈愿记录和 ${counts.achievements} 条成就记录。此操作无法恢复。`} trigger={<button className="button button-danger size-9 p-0" title="删除用户" aria-label={`删除 ${uid}`}><Trash2 size={15} /></button>}>
      <form action={deleteUserAction} className="space-y-3"><input type="hidden" name="csrf" value={csrf} /><input type="hidden" name="uid" value={uid} />
        <label className="block text-sm">输入完整 UID<input className="input mt-1" name="confirmation" required /></label>
        <label className="block text-sm">输入当前 TOTP<input className="input mt-1" name="totp" inputMode="numeric" pattern="[0-9]{6}" required /></label>
        <Submit danger>永久删除</Submit>
      </form>
    </Confirm>
  </div>;
}

function Confirm({ title, description, trigger, children }: { title: string; description: string; trigger: React.ReactNode; children: React.ReactNode }) {
  return <AlertDialog.Root><AlertDialog.Trigger asChild>{trigger}</AlertDialog.Trigger><AlertDialog.Portal><AlertDialog.Overlay className="dialog-overlay" /><AlertDialog.Content className="dialog panel">
    <AlertDialog.Title className="text-lg font-semibold">{title}</AlertDialog.Title><AlertDialog.Description className="muted my-3 text-sm leading-6">{description}</AlertDialog.Description>{children}<AlertDialog.Cancel asChild><button className="button mt-3 w-full">取消</button></AlertDialog.Cancel>
  </AlertDialog.Content></AlertDialog.Portal></AlertDialog.Root>;
}

function Submit({ children, danger = false }: { children: React.ReactNode; danger?: boolean }) {
  return <button className={`button w-full ${danger ? "button-danger" : "button-primary"}`} type="submit">{children}</button>;
}
