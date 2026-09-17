// Changes the login behind a store or a driver, on an admin's behalf.
//
// The store's own row is editable through RLS, so the admin screens write it
// directly. The login is not: an email address and a password live in
// auth.users, which only the service role may touch, and a username has to be
// claimed atomically or two accounts end up with the same one.
//
// A shop owner who forgets their password, mistypes their email at signup, or
// hands the shop to somebody else, rings the operator — who until now could do
// nothing but create a second account.
//
// Request (authenticated admin):
//   { user_id, email?, password?, username?, full_name?, phone? }
// Every field is optional; only what is sent is changed. Returns what changed
// so the caller can say so rather than guess.
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

// The same shape the signup form accepts, so an address an admin sets cannot
// be one the owner could never have registered themselves.
const EMAIL = /^[^\s@]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/;
const USERNAME = /^[A-Za-z0-9._]{3,20}$/;

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
    const actor = userData?.user;
    if (!actor) return json({ error: "UNAUTHORIZED" }, 401);

    const asAdmin = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const body = await req.json().catch(() => ({}));
    const userId = `${body.user_id ?? ""}`;
    if (!userId) return json({ error: "INVALID_REQUEST" }, 400);

    // Which account this is decides which permission the caller needs: the
    // person who may approve stores is not automatically the person who may
    // reset a rider's password, and neither may touch another admin.
    const { data: target } = await service
      .from("profiles")
      .select("id, role")
      .eq("id", userId)
      .maybeSingle();
    if (!target) return json({ error: "NOT_FOUND" }, 404);
    if (target.role === "admin") return json({ error: "FORBIDDEN" }, 403);

    const permission = target.role === "vendor"
      ? "vendors.approve"
      : target.role === "driver"
      ? "drivers.approve"
      : "users.manage";
    const { data: allowed } = await asAdmin.rpc("has_permission", {
      p_key: permission,
    });
    if (allowed !== true) return json({ error: "FORBIDDEN" }, 403);

    const email = `${body.email ?? ""}`.trim().toLowerCase();
    const password = `${body.password ?? ""}`;
    const username = `${body.username ?? ""}`.trim();
    const fullName = `${body.full_name ?? ""}`.trim();
    const hasPhone = body.phone !== undefined;
    const phone = `${body.phone ?? ""}`.trim();

    if (email && !EMAIL.test(email)) return json({ error: "INVALID_EMAIL" }, 400);
    if (password && password.length < 8) {
      return json({ error: "WEAK_PASSWORD" }, 400);
    }
    if (username && !USERNAME.test(username)) {
      return json({ error: "INVALID_USERNAME" }, 400);
    }

    const changed: string[] = [];

    // The login first. If it fails nothing else has been written, which is
    // the order that leaves the least to explain.
    if (email || password) {
      const attributes: { email?: string; password?: string; email_confirm?: boolean } = {};
      if (email) {
        attributes.email = email;
        // The admin is standing with the owner; a confirmation link sent to
        // an address the shop may not be able to read would lock them out of
        // the account they just asked to have fixed.
        attributes.email_confirm = true;
      }
      if (password) attributes.password = password;

      const { error } = await service.auth.admin.updateUserById(
        userId,
        attributes,
      );
      if (error) {
        const message = `${error.message ?? ""}`.toLowerCase();
        if (message.includes("already")) {
          return json({ error: "USER_ALREADY_EXISTS" }, 409);
        }
        console.error("updateUserById failed", error);
        return json({ error: "UPDATE_FAILED" }, 500);
      }
      if (email) changed.push("email");
      if (password) changed.push("password");
    }

    if (username) {
      // Claimed through the database so the uniqueness check and the write
      // are one statement; two operators typing the same name at once get one
      // winner and one refusal, not two accounts sharing a login name.
      const { error } = await service.rpc("admin_set_username", {
        p_user_id: userId,
        p_username: username,
      });
      if (error) {
        const message = `${error.message ?? ""}`;
        if (message.includes("USERNAME_TAKEN")) {
          return json({ error: "USERNAME_TAKEN" }, 409);
        }
        if (message.includes("INVALID_USERNAME")) {
          return json({ error: "INVALID_USERNAME" }, 400);
        }
        console.error("admin_set_username failed", error);
        return json({ error: "UPDATE_FAILED" }, 500);
      }
      changed.push("username");
    }

    const profile: Record<string, unknown> = {};
    if (fullName) profile.full_name = fullName;
    // An empty phone is a deletion, not "leave it alone" — so it is only
    // written when the caller actually sent the field.
    if (hasPhone) profile.phone = phone || null;
    if (Object.keys(profile).length > 0) {
      const { error } = await asAdmin
        .from("profiles")
        .update(profile)
        .eq("id", userId);
      if (error) {
        console.error("profile update failed", error);
        return json({ error: "UPDATE_FAILED" }, 500);
      }
      changed.push(...Object.keys(profile));
    }

    if (changed.length === 0) return json({ error: "NOTHING_TO_UPDATE" }, 400);

    // A password reset somebody else performed is exactly the kind of thing
    // that has to be answerable for afterwards.
    await service.from("admin_audit_log").insert({
      actor_id: actor.id,
      action: `${target.role}.update_account`,
      target_type: "profile",
      target_id: userId,
      detail: { changed },
    });

    return json({ updated: true, changed });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
