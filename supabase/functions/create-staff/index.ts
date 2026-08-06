// Creates a brand-new staff account with an email and password.
//
// Signing somebody up normally goes through the app, which makes a customer.
// Staff are different: an admin creates the login on their behalf, so it needs
// the Auth admin API — and that needs the service role key, which is exactly
// why this cannot happen in the client.
//
// Request (authenticated, unrestricted admin only):
//   { email, password, full_name, role_id? }
//
// `role_id` null means the new account is unrestricted, so it is a deliberate
// choice the caller has to make rather than a default that quietly hands over
// the whole platform.
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    if (userError || !userData.user) return json({ error: "UNAUTHORIZED" }, 401);

    // Creating an admin is how a limited account would escalate itself, so
    // this is restricted to an admin who holds no role at all — the owner.
    const { data: caller } = await admin
      .from("profiles")
      .select("role, admin_role_id, is_blocked, deleted_at")
      .eq("id", userData.user.id)
      .maybeSingle();
    if (
      !caller || caller.role !== "admin" || caller.admin_role_id !== null ||
      caller.is_blocked || caller.deleted_at !== null
    ) {
      return json({ error: "FORBIDDEN" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const email = `${body.email ?? ""}`.trim().toLowerCase();
    const password = `${body.password ?? ""}`;
    const fullName = `${body.full_name ?? ""}`.trim();
    const roleId = body.role_id ?? null;

    if (!email.includes("@") || password.length < 8 || !fullName) {
      return json({ error: "INVALID_REQUEST" }, 400);
    }

    const { data: created, error: createError } = await admin.auth.admin
      .createUser({
        email,
        password,
        // Staff are created by a person who already knows who they are; making
        // them confirm an email before they can work is friction with no
        // security value here.
        email_confirm: true,
        user_metadata: { full_name: fullName, role: "admin" },
      });

    if (createError || !created.user) {
      const message = `${createError?.message ?? ""}`;
      if (message.toLowerCase().includes("already")) {
        // Promote instead — the account exists, it just is not staff yet.
        return json({ error: "USER_ALREADY_EXISTS" }, 409);
      }
      console.error("createUser failed", createError);
      return json({ error: "CREATE_FAILED" }, 500);
    }

    // The signup trigger writes a customer profile; this makes it staff. Done
    // with the service role rather than the RPC because the caller has already
    // been checked above and the profile may not exist for a moment yet.
    const { error: profileError } = await admin
      .from("profiles")
      .update({
        role: "admin",
        admin_role_id: roleId,
        full_name: fullName,
        role_confirmed: true,
      })
      .eq("id", created.user.id);

    if (profileError) {
      // Leaving a half-made account behind would be an email nobody can use
      // and nobody can re-register.
      await admin.auth.admin.deleteUser(created.user.id);
      console.error("profile update failed", profileError);
      return json({ error: "CREATE_FAILED" }, 500);
    }

    await admin.rpc("log_admin_action", {
      p_action: "staff.create",
      p_target_type: "profile",
      p_target_id: created.user.id,
      p_detail: { email, role_id: roleId },
    });

    return json({ created: true, user_id: created.user.id });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
