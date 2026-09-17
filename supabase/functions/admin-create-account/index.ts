// Creates a complete store or driver account on an admin's behalf: the login
// (email + password) and everything the account needs to start working.
//
// A normal signup is self-service: the person registers, picks a role, fills
// the onboarding form, and waits for approval. An admin onboarding a store in
// person needs all of that in one step, which requires the Auth admin API and
// therefore the service role — so it cannot happen in the client.
//
// Request (authenticated admin):
//   {
//     kind: "vendor" | "driver",
//     email, password, full_name, phone?,
//     approve?: boolean,             // default true
//     vendor?: { name, category_id, address_text, lat, lng, description?,
//                phone?, min_order_amount?, avg_prep_minutes?, delivery_fee?,
//                billing_model?, commission_rate?, subscription_fee?,
//                delivery_radius_km?, logo_url?, cover_url? },
//     driver?: { vehicle_type? }
//   }
//
// Only the login is created with the service role. The store row and the
// driver approval are written with the caller's own token, so the existing
// RLS policies, platform-terms triggers and the audit trail apply exactly as
// they do when the admin edits these by hand.
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

const num = (v: unknown, fallback: number) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await service.auth.getUser(jwt);
    if (userError || !userData.user) return json({ error: "UNAUTHORIZED" }, 401);

    // Acts as the admin from here on.
    const asAdmin = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const body = await req.json().catch(() => ({}));
    const kind = body.kind === "driver" ? "driver" : body.kind === "vendor" ? "vendor" : null;
    if (!kind) return json({ error: "INVALID_REQUEST" }, 400);

    const permission = kind === "vendor" ? "vendors.approve" : "drivers.approve";
    const { data: allowed } = await asAdmin.rpc("has_permission", { p_key: permission });
    if (allowed !== true) return json({ error: "FORBIDDEN" }, 403);

    const email = `${body.email ?? ""}`.trim().toLowerCase();
    const password = `${body.password ?? ""}`;
    const fullName = `${body.full_name ?? ""}`.trim();
    const phone = `${body.phone ?? ""}`.trim() || null;
    // Optional: a login name the account can sign in with instead of its
    // email. The signup trigger ignores one that is already taken.
    const username = `${body.username ?? ""}`.trim() || null;
    const approve = body.approve !== false;

    if (!email.includes("@") || !fullName) {
      return json({ error: "INVALID_REQUEST" }, 400);
    }
    if (password.length < 8) return json({ error: "WEAK_PASSWORD" }, 400);

    const vendor = body.vendor ?? {};
    if (kind === "vendor") {
      const name = `${vendor.name ?? ""}`.trim();
      if (!name || !vendor.category_id || !`${vendor.address_text ?? ""}`.trim()) {
        return json({ error: "STORE_DETAILS_REQUIRED" }, 400);
      }
      if (!Number.isFinite(Number(vendor.lat)) || !Number.isFinite(Number(vendor.lng))) {
        return json({ error: "STORE_LOCATION_REQUIRED" }, 400);
      }
    }

    const { data: created, error: createError } = await service.auth.admin.createUser({
      email,
      password,
      // The admin already knows who this is; a confirmation email would only
      // stop them signing in on the spot.
      email_confirm: true,
      // handle_new_user reads these: the profile is created with this role
      // already confirmed, and a driver row is created for a driver.
      user_metadata: { full_name: fullName, phone, role: kind, username },
    });

    if (createError || !created.user) {
      const message = `${createError?.message ?? ""}`.toLowerCase();
      if (message.includes("already")) return json({ error: "USER_ALREADY_EXISTS" }, 409);
      console.error("createUser failed", createError);
      return json({ error: "CREATE_FAILED" }, 500);
    }
    const userId = created.user.id;

    // Anything below failing leaves a login with no store behind it, which
    // nobody could use or re-register — so the login is removed again.
    const rollback = async (reason: unknown, code = "CREATE_FAILED") => {
      console.error("account setup failed", reason);
      await service.auth.admin.deleteUser(userId).catch(() => {});
      return json({ error: code, detail: `${(reason as { message?: string })?.message ?? ""}` }, 500);
    };

    let vendorId: string | null = null;

    if (kind === "vendor") {
      const billing = vendor.billing_model === "subscription" ? "subscription" : "commission";
      const { data: row, error } = await asAdmin
        .from("vendors")
        .insert({
          owner_id: userId,
          name: `${vendor.name}`.trim(),
          description: `${vendor.description ?? ""}`.trim() || null,
          category_id: vendor.category_id,
          phone: `${vendor.phone ?? ""}`.trim() || phone,
          address_text: `${vendor.address_text}`.trim(),
          lat: Number(vendor.lat),
          lng: Number(vendor.lng),
          min_order_amount: Math.max(0, num(vendor.min_order_amount, 0)),
          avg_prep_minutes: Math.max(1, Math.round(num(vendor.avg_prep_minutes, 20))),
          delivery_fee: Math.max(0, num(vendor.delivery_fee, 0)),
          delivery_radius_km: Math.max(0.5, num(vendor.delivery_radius_km, 10)),
          billing_model: billing,
          commission_rate: billing === "commission"
            ? Math.min(100, Math.max(0, num(vendor.commission_rate, 10)))
            : 0,
          subscription_fee: billing === "subscription"
            ? Math.max(0, num(vendor.subscription_fee, 0))
            : 0,
          logo_url: vendor.logo_url || null,
          cover_url: vendor.cover_url || null,
          approval_status: approve ? "active" : "pending",
          // Open for business straight away.
          //
          // `is_open` defaults to false, which is right for a shop that
          // registered itself and is still filling in its menu — it decides
          // when it is ready. A shop an operator sets up in person is ready
          // now: the operator is standing in it. Leaving it closed meant
          // signing in as the owner afterwards just to flip a switch, and
          // until somebody did, the store was invisible to customers for no
          // reason either of them could see.
          //
          // A store held back for review stays shut: it cannot take orders
          // while it is pending anyway, and it should not open the moment it
          // is approved without anybody saying so.
          is_open: approve,
        })
        .select("id")
        .single();
      if (error || !row) return await rollback(error);
      vendorId = row.id;
    } else {
      const vehicle = `${body.driver?.vehicle_type ?? ""}`.trim();
      if (vehicle) {
        const { error } = await asAdmin
          .from("drivers")
          .update({ vehicle_type: vehicle })
          .eq("id", userId);
        if (error) return await rollback(error);
      }
      if (approve) {
        const { error } = await asAdmin.rpc("admin_set_driver_status", {
          p_driver_id: userId,
          p_status: "active",
          p_reason: null,
        });
        if (error) return await rollback(error);
      }
    }

    // log_admin_action is not callable by clients, so the entry is written
    // directly, attributed to the admin who made the request.
    await service.from("admin_audit_log").insert({
      actor_id: userData.user.id,
      action: `${kind}.create_account`,
      target_type: kind === "vendor" ? "vendor" : "profile",
      target_id: vendorId ?? userId,
      detail: { email, approved: approve },
    });

    return json({ created: true, user_id: userId, vendor_id: vendorId });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
