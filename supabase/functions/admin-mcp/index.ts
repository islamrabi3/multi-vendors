// Lets Claude work the admin console: an MCP server over HTTP.
//
// An admin makes a key on the dashboard (System → Claude keys) and gives it
// to Claude Code or Claude Desktop. Each request carries that key; this
// function works out whose it is and then runs the tool *as that admin* — not
// with the service role.
//
// "As that admin" is literal. The tool runs in a transaction that has been
// switched to the `authenticated` role with the admin's id in the request
// claims, which is precisely what PostgREST does for a signed-in dashboard
// session. So `auth.uid()`, `has_permission()` and every row policy give the
// answers they would give that admin, and a key can never do more than its
// owner. The claims also say the request came through here, which is how the
// admin log marks an action as Claude's.
//
// POST /functions/v1/admin-mcp
//   Authorization: Bearer kin_mcp_…
//   body: a JSON-RPC 2.0 message (initialize, tools/list, tools/call, ping)
import { createClient } from "npm:@supabase/supabase-js@2";
import postgres from "npm:postgres@3.4.5";

import { handleRpc } from "./protocol.ts";
import { authenticate, callAs } from "./session.ts";
import { type Accounts, describeTools, ToolError } from "./tools.ts";

// One small pool per worker. `prepare: false` because the connection may go
// through the transaction pooler, which cannot keep prepared statements.
const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, {
  max: 2,
  idle_timeout: 20,
  connect_timeout: 10,
  prepare: false,
  onnotice: () => {},
});

// Logins live in auth.users, which only the Auth admin API may write. This is
// the single use of the service role here, reachable only from `create_store`
// and only after the admin's own permission has been checked.
const auth = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
).auth.admin;

const accounts: Accounts = {
  async createLogin({ email, password, fullName, phone, username, role }) {
    const { data, error } = await auth.createUser({
      email,
      password,
      // The admin already knows who this is; a confirmation email would only
      // stop the owner signing in on the spot.
      email_confirm: true,
      // handle_new_user reads these and creates the profile with this role.
      user_metadata: { full_name: fullName, phone, role, username },
    });
    if (error || !data.user) {
      const message = `${error?.message ?? ""}`.toLowerCase();
      if (message.includes("already")) {
        throw new ToolError(
          "USER_ALREADY_EXISTS",
          "An account with this email already exists.",
        );
      }
      if (message.includes("password")) {
        throw new ToolError("WEAK_PASSWORD", error?.message);
      }
      console.error("admin-mcp createUser failed", error);
      throw new ToolError("CREATE_FAILED", "The login could not be created.");
    }
    return data.user.id;
  },
  async deleteLogin(userId) {
    const { error } = await auth.deleteUser(userId);
    if (error) console.error("admin-mcp deleteUser failed", userId, error);
  },
};

function json(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
}

const unauthorized = () =>
  json({ error: "UNAUTHORIZED" }, 401, { "WWW-Authenticate": "Bearer" });

Deno.serve(async (req) => {
  // The protocol allows GET for a server-to-client stream; this server never
  // has anything to push.
  if (req.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405, { Allow: "POST" });
  }

  try {
    const caller = await authenticate(sql, req.headers.get("Authorization"));
    if (!caller) return unauthorized();

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return json({
        jsonrpc: "2.0",
        id: null,
        error: { code: -32700, message: "Parse error" },
      }, 400);
    }

    const answer = await handleRpc(body, {
      listTools: describeTools,
      callTool: (name, args) => callAs(sql, caller, name, args, accounts),
      onError: (error) => console.error("admin-mcp tool failed", error),
    });
    // Only notifications came in: accepted, nothing to say.
    if (answer === null) return new Response(null, { status: 202 });
    return json(answer);
  } catch (error) {
    console.error("admin-mcp failed", error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
