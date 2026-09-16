// Creates a login for somebody who works in a store: a cashier who takes
// orders, a manager who edits the menu.
//
// The store owner is the caller. Only the account creation needs the service
// role; the staff row is written with the owner's own token through
// vendor_attach_staff, so a caller who does not own the store is refused by
// the database rather than by this function alone.
//
// Request (authenticated store owner):
//   { email, password, full_name, permissions: ["orders", "menu"] }
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const ALLOWED = ["orders", "menu", "reviews", "settings"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const authHeader = req.headers.get("Authorization") ?? "";
    const { data: userData } = await service.auth.getUser(
      authHeader.replace("Bearer ", ""),
    );
    const owner = userData?.user;
    if (!owner) return json({ error: "UNAUTHORIZED" }, 401);

    const asOwner = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    // The store this caller owns; a staff member owns none, so they cannot
    // create staff of their own.
    const { data: vendor } = await service
      .from("vendors")
      .select("id")
      .eq("owner_id", owner.id)
      .maybeSingle();
    if (!vendor) return json({ error: "FORBIDDEN" }, 403);

    const body = await req.json().catch(() => ({}));
    const email = `${body.email ?? ""}`.trim().toLowerCase();
    const password = `${body.password ?? ""}`;
    const fullName = `${body.full_name ?? ""}`.trim();
    const permissions = Array.isArray(body.permissions)
      ? [...new Set(body.permissions.map((p: unknown) => `${p}`))]
        .filter((p) => ALLOWED.includes(p))
      : [];

    if (!email.includes("@") || !fullName) {
      return json({ error: "INVALID_REQUEST" }, 400);
    }
    if (password.length < 8) return json({ error: "WEAK_PASSWORD" }, 400);
    if (permissions.length === 0) return json({ error: "NO_PERMISSIONS" }, 400);

    const { data: created, error: createError } = await service.auth.admin
      .createUser({
        email,
        password,
        email_confirm: true,
        // The store console is a vendor-role app; what this account may do
        // inside it comes from the staff row, not from the role.
        user_metadata: {
          full_name: fullName,
          role: "vendor",
          username: `${body.username ?? ""}`.trim() || null,
        },
      });

    if (createError || !created.user) {
      const message = `${createError?.message ?? ""}`.toLowerCase();
      if (message.includes("already")) {
        return json({ error: "USER_ALREADY_EXISTS" }, 409);
      }
      console.error("createUser failed", createError);
      return json({ error: "CREATE_FAILED" }, 500);
    }

    const { error: attachError } = await asOwner.rpc("vendor_attach_staff", {
      p_user_id: created.user.id,
      p_vendor_id: vendor.id,
      p_full_name: fullName,
      p_permissions: permissions,
    });

    if (attachError) {
      // A login with no store behind it would be an email nobody can use.
      await service.auth.admin.deleteUser(created.user.id).catch(() => {});
      console.error("vendor_attach_staff failed", attachError);
      return json({ error: "CREATE_FAILED" }, 500);
    }

    return json({ created: true, user_id: created.user.id });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
