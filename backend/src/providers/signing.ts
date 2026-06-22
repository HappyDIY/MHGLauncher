import { createHash, randomBytes } from "node:crypto";

const salts = { prod: "JwYDpKvLj6MrMqqYU6jTKF17KNO2PXoS", x4: "xV8v4Qu54lUKrEYFZkJhB8cuOh9Asafs", lk2: "sidQFEglajEz7FA0Aj7HQPV88zpf17SO" };

export function sign(kind: keyof typeof salts, body = "", query = "", generation = 2): string {
  const t = Math.floor(Date.now() / 1000), r = randomBytes(6).toString("base64url").toLowerCase().slice(0, 6);
  const normalized = new URLSearchParams([...new URLSearchParams(query).entries()].sort()).toString();
  const value = `salt=${salts[kind]}&t=${t}&r=${r}${generation === 2 ? `&b=${body}&q=${normalized}` : ""}`;
  return `${t},${r},${createHash("md5").update(value).digest("hex")}`;
}

export function cookies(raw: string): Map<string, string> {
  return new Map(raw.split(";").map((value) => value.trim().split("=", 2)).filter((value) => value.length === 2) as [string, string][]);
}
