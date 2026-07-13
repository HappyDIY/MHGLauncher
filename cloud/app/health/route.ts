import { healthy } from "../../src/db";

export async function GET(): Promise<Response> {
  const ok = await healthy();
  return Response.json({ ok }, { status: ok ? 200 : 503 });
}
