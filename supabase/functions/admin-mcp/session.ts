// Turning a key into an admin, and running a tool as that admin.
//
// Kept apart from the HTTP handler so the same code path can be driven
// against a test database.
import type postgres from "npm:postgres@3.4.5";

import {
  type Accounts,
  type Caller,
  type Db,
  findTool,
  runTool,
} from "./tools.ts";

const TOKEN = /^kin_mcp_[0-9a-f]{64}$/;

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/// Whose key this is, or null if it is not a good one. The reason is never
/// said: unknown, revoked, expired and "owner is no longer an admin" all look
/// the same from outside.
export async function authenticate(
  sql: postgres.Sql,
  authorization: string | null,
): Promise<Caller | null> {
  const token = (authorization ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!TOKEN.test(token)) return null;

  const rows = await sql.unsafe(
    "select * from public.admin_mcp_authenticate($1::text)",
    [await sha256Hex(token)],
  );
  const hit = rows[0];
  if (!hit) return null;
  return {
    adminId: hit.admin_id,
    adminName: hit.admin_name,
    tokenId: hit.token_id,
    tokenName: hit.token_name,
  };
}

/// Runs one tool in its own transaction, as the admin. A tool that fails
/// leaves nothing behind: the write and its log line stand or fall together.
export function callAs(
  sql: postgres.Sql,
  caller: Caller,
  name: string,
  args: unknown,
  accounts?: Accounts,
): Promise<unknown> {
  return sql.begin(async (tx) => {
    await tx.unsafe(
      "select set_config('request.jwt.claims', $1::text, true)",
      [JSON.stringify({
        sub: caller.adminId,
        role: "authenticated",
        via: "mcp",
        mcp_token_id: caller.tokenId,
      })],
    );
    // From here on this transaction has the admin's rights and no more.
    await tx.unsafe("set local role authenticated");
    await tx.unsafe("set local statement_timeout = '20s'");
    // A tool that only looks things up cannot change anything even by
    // mistake.
    if (findTool(name)?.readOnly) {
      await tx.unsafe("set local transaction_read_only = on");
    }

    const db: Db = {
      async json<T>(text: string, params: unknown[] = []) {
        const rows = await tx.unsafe(text, params as never[]);
        const first = rows[0];
        return first ? (Object.values(first)[0] as T) : null;
      },
    };
    return await runTool(db, caller, name, args, accounts);
  });
}
