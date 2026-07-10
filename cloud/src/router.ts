import { z } from "zod";
import { issue, requireFresh, requireSession, reverify, verifyGachaUrl } from "./auth";
import { ready } from "./db";
import { bearer, fail, HttpError, json } from "./http";
import * as gacha from "./gacha";

const gachaUrl = z.object({ gacha_url: z.string().url() });
const uidBody = z.object({ uid: z.string().min(1) });
const uploadBody = uidBody.extend({ items: z.array(z.any()) });

export async function dispatch(request: Request): Promise<Response> {
  try {
    await ready();
    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/api\/v1/, "");
    const body = request.method === "POST" ? await request.json() : undefined;
    return await route(request.method, path, url.searchParams, body, request);
  } catch (error) {
    if (error instanceof z.ZodError) return json({ code: "validation_error", message: "请求参数无效", detail: error.issues }, 422);
    return fail(error);
  }
}

async function route(method: string, path: string, query: URLSearchParams, body: unknown, request: Request): Promise<Response> {
  if (method === "POST" && path === "/auth/gacha-url") {
    const proof = await verifyGachaUrl(gachaUrl.parse(body).gacha_url);
    const session = await issue(proof.uid);
    await gacha.upload(proof.uid, proof.items);
    return json(session);
  }
  if (method === "POST" && path === "/auth/reverify") {
    const proof = await verifyGachaUrl(gachaUrl.parse(body).gacha_url);
    return json(await reverify(bearer(request), proof.uid));
  }
  if (method === "GET" && path === "/me") return json(await requireSession(bearer(request)));
  if (method === "GET" && path === "/gacha/entries") {
    const uid = required(query, "uid"); await requireSession(bearer(request), uid);
    return json(await gacha.entries(uid));
  }
  if (method === "GET" && path === "/gacha/end-ids") {
    const uid = required(query, "uid"); await requireSession(bearer(request), uid);
    return json(await gacha.endIds(uid));
  }
  if (method === "POST" && path === "/gacha/upload") {
    const value = uploadBody.parse(body); await requireFresh(bearer(request), value.uid);
    return json(await gacha.upload(value.uid, value.items));
  }
  if (method === "POST" && path === "/gacha/retrieve") {
    const value = uidBody.parse(body); await requireSession(bearer(request), value.uid);
    return json(await gacha.retrieve(value.uid));
  }
  const remove = match(path, /^\/gacha\/([^/]+)$/);
  if (method === "DELETE" && remove) { await requireFresh(bearer(request), remove); return json(await gacha.remove(remove)); }
  throw new HttpError(404, "not_found", "接口不存在");
}

function match(path: string, expression: RegExp): string | null {
  const value = expression.exec(path)?.[1];
  return value ? decodeURIComponent(value) : null;
}

function required(query: URLSearchParams, name: string): string {
  const value = query.get(name);
  if (!value) throw new HttpError(422, "validation_error", `${name} 不能为空`);
  return value;
}
