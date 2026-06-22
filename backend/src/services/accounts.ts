import type { Account, AccountIdentity, GameRole } from "../core/models";
import type { Store } from "../core/database";
import type { Provider } from "../providers/provider";

function role(row: Record<string, unknown>): GameRole {
  return { uid: String(row.uid), nickname: String(row.nickname), region: String(row.region), level: Number(row.level), selected: Boolean(row.selected) };
}

export class AccountService {
  constructor(private readonly store: Store, private readonly provider: Provider) {}

  save(identity: AccountIdentity, credentialRef: string): Account {
    const updated_at = new Date().toISOString();
    this.store.db.prepare(`INSERT INTO account(id,aid,mid,nickname,credential_ref,updated_at) VALUES(1,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET aid=excluded.aid,mid=excluded.mid,nickname=excluded.nickname,
      credential_ref=excluded.credential_ref,updated_at=excluded.updated_at`)
      .run(identity.aid, identity.mid, identity.nickname, credentialRef, updated_at);
    return { aid: identity.aid, mid: identity.mid, nickname: identity.nickname, credential_ref: credentialRef, updated_at };
  }

  get(): Account | null { return (this.store.one("SELECT aid,mid,nickname,credential_ref,updated_at FROM account WHERE id=1") as unknown as Account) ?? null; }

  logout(): void {
    this.store.db.transaction(() => { this.store.db.exec("DELETE FROM roles; DELETE FROM account"); })();
  }

  async syncRoles(credential: string): Promise<GameRole[]> {
    const roles = (await this.provider.getRoles(credential)).map((value, index) => ({ ...value, selected: index === 0 }));
    const insert = this.store.db.prepare("INSERT INTO roles(uid,nickname,region,level,selected) VALUES(?,?,?,?,?)");
    this.store.db.transaction(() => {
      this.store.db.exec("DELETE FROM roles");
      for (const value of roles) insert.run(value.uid, value.nickname, value.region, value.level, Number(value.selected));
    })();
    return roles;
  }

  roles(): GameRole[] { return this.store.all("SELECT * FROM roles ORDER BY selected DESC,uid").map(role); }
  selectedRole(): GameRole | null { const value = this.store.one("SELECT * FROM roles ORDER BY selected DESC,uid LIMIT 1"); return value ? role(value) : null; }
}
