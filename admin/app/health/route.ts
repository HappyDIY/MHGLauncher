import { pool, ready } from "@/lib/db";

export async function GET(): Promise<Response> {
  try { await ready(); await pool().query("SELECT 1"); return Response.json({ ok: true }); }
  catch { return Response.json({ ok: false }, { status: 503 }); }
}
