import type { Account, AccountIdentity, GameRole } from "../core/models";
import type { Store } from "../core/database";
import type { Provider } from "../providers/provider";
import { AppError } from "../core/errors";

function role(row: Record<string, unknown>): GameRole {
  return { uid: String(row.uid), nickname: String(row.nickname), region: String(row.region), level: Number(row.level), selected: Boolean(row.selected) };
}
function account(row: Record<string, unknown>): Account {
  return {
    aid: String(row.aid), mid: String(row.mid), nickname: String(row.nickname),
    credential_ref: String(row.credential_ref), selected: Boolean(row.selected),
    updated_at: String(row.updated_at),
  };
}

export class AccountService {
  constructor(private readonly store: Store, private readonly provider: Provider) {}

  commit(identity: AccountIdentity, roles: GameRole[]): { account: Account; roles: GameRole[] } {
    const updated_at = new Date().toISOString();
    const credentialRef = `keychain:account:${identity.aid}`;
    let selectedUid = String(this.store.one("SELECT uid FROM roles WHERE account_aid=? AND selected=1", identity.aid)?.uid ?? "");
    if (!roles.some(({ uid }) => uid === selectedUid)) selectedUid = roles[0]?.uid ?? "";
    const insertRole = this.store.db.prepare("INSERT INTO roles(uid,account_aid,nickname,region,level,selected) VALUES(?,?,?,?,?,?)");
    this.store.db.transaction(() => {
      this.store.db.exec("UPDATE account SET selected=0");
      this.store.db.prepare(`INSERT INTO account(aid,mid,nickname,credential_ref,selected,updated_at) VALUES(?,?,?,?,1,?)
        ON CONFLICT(aid) DO UPDATE SET mid=excluded.mid,nickname=excluded.nickname,
        credential_ref=excluded.credential_ref,selected=1,updated_at=excluded.updated_at`)
        .run(identity.aid, identity.mid, identity.nickname, credentialRef, updated_at);
      this.store.db.prepare("DELETE FROM roles WHERE account_aid=?").run(identity.aid);
      for (const value of roles) insertRole.run(value.uid, identity.aid, value.nickname, value.region, value.level, Number(value.uid === selectedUid));
    })();
    return {
      account: { aid: identity.aid, mid: identity.mid, nickname: identity.nickname, credential_ref: credentialRef, selected: true, updated_at },
      roles: this.roles(identity.aid),
    };
  }

  list(): Account[] { return this.store.all("SELECT * FROM account ORDER BY selected DESC,updated_at DESC").map(account); }
  get(): Account | null { const value = this.store.one("SELECT * FROM account ORDER BY selected DESC,updated_at DESC LIMIT 1"); return value ? account(value) : null; }

  select(aid: string): Account {
    const value = this.store.one("SELECT * FROM account WHERE aid=?", aid);
    if (!value) throw new AppError("account_missing", "账号不存在", 404);
    this.store.db.transaction(() => {
      this.store.db.exec("UPDATE account SET selected=0");
      this.store.db.prepare("UPDATE account SET selected=1 WHERE aid=?").run(aid);
      const hasSelected = this.store.one("SELECT uid FROM roles WHERE account_aid=? AND selected=1", aid);
      if (!hasSelected) {
        this.store.db.prepare("UPDATE roles SET selected=1 WHERE account_aid=? AND uid=(SELECT uid FROM roles WHERE account_aid=? ORDER BY uid LIMIT 1)").run(aid, aid);
      }
    })();
    return { ...account(value), selected: true };
  }

  selectRole(uid: string): GameRole {
    const current = this.get();
    if (!current) throw new AppError("account_missing", "尚未登录账号", 409);
    const value = this.store.one("SELECT * FROM roles WHERE uid=? AND account_aid=?", uid, current.aid);
    if (!value) throw new AppError("role_missing", "角色不存在", 404);
    this.store.db.transaction(() => {
      this.store.db.prepare("UPDATE roles SET selected=0 WHERE account_aid=?").run(current.aid);
      this.store.db.prepare("UPDATE roles SET selected=1 WHERE account_aid=? AND uid=?").run(current.aid, uid);
    })();
    return { ...role(value), selected: true };
  }

  logout(aid?: string): void {
    const current = this.get();
    const target = aid ?? current?.aid;
    if (!target) return;
    const removedSelected = current?.aid === target;
    this.store.db.prepare("DELETE FROM account WHERE aid=?").run(target);
    if (removedSelected) {
      const next = this.store.one("SELECT aid FROM account ORDER BY updated_at DESC LIMIT 1")?.aid;
      if (next) this.select(String(next));
    }
  }

  async prepareRoles(identity: AccountIdentity): Promise<GameRole[]> {
    return (await this.provider.getRoles(identity.credential)).map((value, index) => ({ ...value, selected: index === 0 }));
  }

  async syncRoles(aid: string, credential: string): Promise<GameRole[]> {
    const target = this.list().find((value) => value.aid === aid);
    if (!target) throw new AppError("account_missing", "账号不存在", 404);
    const identity = await this.provider.identifyCredential(credential);
    if (identity.aid !== target.aid || identity.mid !== target.mid) throw new AppError("credential_identity_mismatch", "凭据与账号身份不匹配", 403);
    const roles = await this.prepareRoles(identity);
    let selectedUid = String(this.store.one("SELECT uid FROM roles WHERE account_aid=? AND selected=1", aid)?.uid ?? "");
    if (!roles.some(({ uid }) => uid === selectedUid)) selectedUid = roles[0]?.uid ?? "";
    const insert = this.store.db.prepare("INSERT INTO roles(uid,account_aid,nickname,region,level,selected) VALUES(?,?,?,?,?,?)");
    this.store.db.transaction(() => {
      this.store.db.prepare("DELETE FROM roles WHERE account_aid=?").run(aid);
      for (const value of roles) insert.run(value.uid, aid, value.nickname, value.region, value.level, Number(value.uid === selectedUid));
    })();
    return this.roles(aid);
  }

  roles(aid = this.get()?.aid): GameRole[] { return aid ? this.store.all("SELECT * FROM roles WHERE account_aid=? ORDER BY selected DESC,uid", aid).map(role) : []; }
  selectedRole(): GameRole | null { const current = this.get(); const value = current ? this.store.one("SELECT * FROM roles WHERE account_aid=? ORDER BY selected DESC,uid LIMIT 1", current.aid) : null; return value ? role(value) : null; }
}
