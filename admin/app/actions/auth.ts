"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { authenticate } from "@/lib/auth";
import { createSession, revokeCurrentSession, verifyMutation } from "@/lib/session";
import { pool } from "@/lib/db";
import { revalidatePath } from "next/cache";

const loginSchema = z.object({ email: z.string().email().max(254), password: z.string().min(12).max(256), code: z.string().min(6).max(32) });

export async function loginAction(formData: FormData): Promise<void> {
  const parsed = loginSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success || !await authenticate(parsed.data.email, parsed.data.password, parsed.data.code)) redirect("/login?error=1");
  await createSession();
  redirect("/");
}

export async function logoutAction(): Promise<void> {
  await revokeCurrentSession();
  redirect("/login");
}

export async function revokeOtherSessionsAction(formData: FormData): Promise<void> {
  const session = await verifyMutation(formData.get("csrf"));
  await pool().query("UPDATE admin.admin_sessions SET revoked_at=now() WHERE revoked_at IS NULL AND token_hash<>$1", [session.tokenHash]);
  revalidatePath("/security");
}
