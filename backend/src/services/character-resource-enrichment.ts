import type { GameCharacter } from "../core/models";
import type { Catalog, CharacterAssetKind } from "./gacha-resource-catalog";

type JSONObject = Record<string, unknown>;
type Endpoint = (name: string) => string;
type CachedEndpoint = (remote: string | null | undefined) => string | null;

export function localizeCharacter(
  character: GameCharacter,
  catalog: Catalog | undefined,
  endpoint: Endpoint,
  cachedEndpoint: CachedEndpoint,
): GameCharacter {
  const payload = localizeImages(cloneObject(character.payload), cachedEndpoint);
  const cachedAvatar = cachedEndpoint(character.icon_url);
  if (!catalog) return { ...character, icon_url: cachedAvatar, payload };
  const avatar = asset(catalog, "avatars", character.avatar_id);
  rewriteObjectIcon(payload, "avatars", "id", catalog, endpoint);
  rewriteObjectIcon(object(payload?.base), "avatars", "id", catalog, endpoint);
  rewriteWeapon(object(payload?.weapon), catalog, endpoint);
  rewriteWeapon(object(payload?.base)?.weapon, catalog, endpoint);
  rewriteList(payload?.relics, "reliquaries", "id", catalog, endpoint);
  rewriteList(payload?.skills, "skills", "skill_id", catalog, endpoint);
  rewriteList(payload?.constellations, "talents", "id", catalog, endpoint);
  return { ...character, icon_url: avatar ? endpoint(avatar) : cachedAvatar, payload };
}

function rewriteWeapon(value: unknown, catalog: Catalog, endpoint: Endpoint): void {
  rewriteObjectIcon(object(value), "weapons", "id", catalog, endpoint);
}

function rewriteList(
  value: unknown,
  kind: CharacterAssetKind,
  idKey: string,
  catalog: Catalog,
  endpoint: Endpoint,
): void {
  if (!Array.isArray(value)) return;
  value.forEach((entry) => rewriteObjectIcon(object(entry), kind, idKey, catalog, endpoint));
}

function rewriteObjectIcon(
  value: JSONObject | undefined,
  kind: CharacterAssetKind,
  idKey: string,
  catalog: Catalog,
  endpoint: Endpoint,
): void {
  if (!value) return;
  const name = asset(catalog, kind, value[idKey]);
  value.icon = name ? endpoint(name) : value.icon ?? null;
}

function asset(catalog: Catalog, kind: CharacterAssetKind, id: unknown): string | undefined {
  const key = typeof id === "string" || typeof id === "number" ? String(id) : "";
  return key ? catalog.character_assets[kind][key] : undefined;
}

function localizeImages(value: JSONObject | undefined, cached: CachedEndpoint): JSONObject | undefined {
  if (!value) return value;
  const visit = (current: unknown): void => {
    if (Array.isArray(current)) return current.forEach(visit);
    const entry = object(current);
    if (!entry) return;
    for (const [key, child] of Object.entries(entry)) {
      if (["icon", "image", "side_icon"].includes(key)) {
        entry[key] = typeof child === "string" ? cached(child) : null;
      }
      else visit(child);
    }
  };
  visit(value); return value;
}

function cloneObject(value: unknown): JSONObject | undefined {
  const entry = object(value);
  return entry ? structuredClone(entry) : undefined;
}
function object(value: unknown): JSONObject | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as JSONObject : undefined;
}
