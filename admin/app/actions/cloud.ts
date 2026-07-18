"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { verifyOwnerTotp } from "@/lib/auth";
import { cloudRequest } from "@/lib/cloud";
import { verifyMutation } from "@/lib/session";

const uid = z.string().regex(/^\d{9,10}$/);
const release = z.object({ version: z.string().min(1), download_url: z.string().url(), sha256: z.string().length(64),
  size: z.coerce.number().int().positive(), changelog: z.string().min(1).max(20_000) });

export async function revokeSessionsAction(form: FormData): Promise<void> {
  const session = await verifyMutation(form.get("csrf")), value = uid.parse(form.get("uid"));
  await cloudRequest(`/users/${value}/revoke-sessions`, session.email, { method: "POST" });
  revalidatePath("/users"); revalidatePath("/");
}

export async function deleteUserAction(form: FormData): Promise<void> {
  const session = await verifyMutation(form.get("csrf")), value = uid.parse(form.get("uid"));
  if (form.get("confirmation") !== value || !await verifyOwnerTotp(String(form.get("totp") ?? ""))) throw new Error("删除确认或验证码无效");
  await cloudRequest(`/users/${value}`, session.email, { method: "DELETE" });
  revalidatePath("/users"); revalidatePath("/");
}

export async function createReleaseAction(form: FormData): Promise<void> {
  const session = await verifyMutation(form.get("csrf"));
  const value = release.parse(Object.fromEntries(form));
  await cloudRequest("/releases", session.email, { method: "POST", body: JSON.stringify(value) });
  revalidatePath("/releases");
}

export async function publishReleaseAction(form: FormData): Promise<void> {
  const session = await verifyMutation(form.get("csrf"));
  const id = z.coerce.number().int().positive().parse(form.get("id"));
  const operation = form.get("operation") === "rollback" ? "rollback" : "publish";
  await cloudRequest(`/releases/${id}/${operation}`, session.email, { method: "POST" });
  revalidatePath("/releases"); revalidatePath("/");
}
