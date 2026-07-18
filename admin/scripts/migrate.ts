import { pool, ready } from "../lib/db";

await ready();
console.log("管理数据库迁移完成");
await pool().end();
