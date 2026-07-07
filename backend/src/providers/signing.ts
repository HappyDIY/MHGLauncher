import { createHash, randomBytes } from "node:crypto";

const salts = { prod: "JwYDpKvLj6MrMqqYU6jTKF17KNO2PXoS", x4: "xV8v4Qu54lUKrEYFZkJhB8cuOh9Asafs", lk2: "sidQFEglajEz7FA0Aj7HQPV88zpf17SO" };
const alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";

export function sign(kind: keyof typeof salts, body = "", query = "", generation = 2): string {
  const t = Math.floor(Date.now() / 1000), r = kind === "x4" ? String(100000 + randomBytes(2).readUInt16BE() % 100000) : randomText();
  const normalized = new URLSearchParams([...new URLSearchParams(query).entries()].sort()).toString();
  const value = `salt=${salts[kind]}&t=${t}&r=${r}${generation === 2 ? `&b=${kind === "prod" && !body ? "{}" : body}&q=${normalized}` : ""}`;
  return `${t},${r},${createHash("md5").update(value).digest("hex")}`;
}

function randomText(): string {
  return [...randomBytes(6)].map((value) => alphabet[value % alphabet.length]).join("");
}

export function cookies(raw: string): Map<string, string> {
  const map = new Map<string, string>();
  for (const item of raw.replaceAll(" ", "").split(";")) {
    const index = item.indexOf("=");
    if (index <= 0) continue;
    const key = item.slice(0, index);
    if (!map.has(key)) map.set(key, item.slice(index + 1));
  }
  return map;
}
