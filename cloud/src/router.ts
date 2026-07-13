import { z } from "zod";
import { issue, requireFresh, requireSession, reverify, revoke, verifyGachaUrl } from "./auth";
import { ready } from "./db";
import { bearer, fail, HttpError, json } from "./http";
import * as gacha from "./gacha";

const gachaUrl = z.object({ gacha_url: z.string().url() });
const uploadBody = z.object({ items: z.array(z.any()) });

export async function dispatch(request: Request): Promise<Response> {
  try {
    await ready();
    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/api\/v1/, "");
    const body = request.method === "POST" ? await request.json() : undefined;
    return await route(request.method, path, body, request);
  } catch (error) {
    if (error instanceof z.ZodError) return json({ code: "validation_error", message: "请求参数无效", detail: error.issues }, 422);
    return fail(error);
  }
}

async function route(method: string, path: string, body: unknown, request: Request): Promise<Response> {
  if (method === "POST" && path === "/auth/gacha-url") {
    const proof = await verifyGachaUrl(gachaUrl.parse(body).gacha_url);
    const session = await issue(proof.uid, (client) => gacha.uploadWithClient(client, proof.uid, proof.items).then(() => undefined));
    return json(session);
  }
  if (method === "POST" && path === "/auth/reverify") {
    const proof = await verifyGachaUrl(gachaUrl.parse(body).gacha_url);
    return json(await reverify(bearer(request), proof.uid));
  }
  if (method === "GET" && path === "/me") return json(await requireSession(bearer(request)));
  if (method === "POST" && path === "/auth/revoke") { await revoke(bearer(request)); return new Response(null, { status: 204 }); }
  if (method === "GET" && path === "/gacha/entries") {
    const session = await requireSession(bearer(request)); return json(await gacha.entries(session.uid));
  }
  if (method === "GET" && path === "/gacha/end-ids") {
    const session = await requireSession(bearer(request)); return json(await gacha.endIds(session.uid));
  }
  if (method === "POST" && path === "/gacha/upload") {
    const value = uploadBody.parse(body), session = await requireFresh(bearer(request));
    return json(await gacha.upload(session.uid, value.items));
  }
  if (method === "POST" && path === "/gacha/retrieve") {
    const session = await requireSession(bearer(request)); return json(await gacha.retrieve(session.uid));
  }
  if (method === "DELETE" && path === "/gacha") {
    const session = await requireFresh(bearer(request)); return json(await gacha.remove(session.uid));
  }
  throw new HttpError(404, "not_found", "接口不存在");
}
