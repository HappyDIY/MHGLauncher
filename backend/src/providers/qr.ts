import { AppError } from "../core/errors";
import type { QRSession } from "../core/models";

type JSONValue = Record<string, any>;

export function qrStatus(data: JSONValue): QRSession["status"] {
  const raw = String(data.status ?? data.stat ?? data.qr_status).toLowerCase();
  if (["confirmed", "confirm", "3"].includes(raw)) return "confirmed";
  if (["scanned", "scan", "2"].includes(raw)) return "scanned";
  if (["expired", "expire", "4"].includes(raw)) return "expired";
  return "created";
}

export function qrConfirmedPayload(data: JSONValue): { user: JSONValue; token: string } {
  const payload = (data.payload ?? data) as JSONValue;
  const token = (payload.tokens as JSONValue[] | undefined)
    ?.find((value) => Number(value.token_type) === 1)?.token;
  const user = (payload.user_info ?? payload.user) as JSONValue | undefined;
  if (!user || !token) throw new AppError("qr_payload_invalid", "二维码登录结果缺少凭据", 502);
  return { user, token: String(token) };
}
