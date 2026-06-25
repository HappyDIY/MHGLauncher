import { AppError } from "../core/errors";
import type { MobileCaptchaVerification } from "../core/models";

type JSONValue = Record<string, any>;

export interface AigisSession {
  session_id: string;
  mmt_type: number;
  data: string;
}

export function parseAigisSession(raw: string | null): AigisSession | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as Partial<AigisSession>;
    if (typeof value.session_id !== "string" || typeof value.data !== "string") return null;
    return { session_id: value.session_id, mmt_type: Number(value.mmt_type ?? 0), data: value.data };
  } catch {
    return null;
  }
}

export function verificationFromAigis(session: AigisSession): MobileCaptchaVerification {
  const data = JSON.parse(session.data) as JSONValue;
  const gt = String(data.gt ?? ""), challenge = String(data.challenge ?? "");
  if (!gt || !challenge) throw new AppError("aigis_payload_invalid", "米游社验证数据不完整", 502);
  return { gt, challenge, session_id: session.session_id };
}

export function createAigisHeader(sessionId: string, challenge: string, validate: string): string {
  const payload = {
    geetest_challenge: challenge,
    geetest_validate: validate,
    geetest_seccode: `${validate}|jordan`,
  };
  return `${sessionId};${Buffer.from(JSON.stringify(payload)).toString("base64")}`;
}
