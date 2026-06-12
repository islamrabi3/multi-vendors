// Creates a Paymob payment intention for an order and returns the unified
// checkout URL. Caller must be the order's customer (JWT verified by the
// platform). Amounts come from the order row — never from the client.
//
// Secrets required:
//   PAYMOB_SECRET_KEY, PAYMOB_PUBLIC_KEY, PAYMOB_INTEGRATION_ID
import { createClient } from "npm:@supabase/supabase-js@2";

const PAYMOB_BASE = "https://accept.paymob.com";

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
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const secretKey = Deno.env.get("PAYMOB_SECRET_KEY");
    const publicKey = Deno.env.get("PAYMOB_PUBLIC_KEY");
    const integrationId = Deno.env.get("PAYMOB_INTEGRATION_ID");

    if (!secretKey || !publicKey || !integrationId) {
      return json({ error: "PAYMOB_NOT_CONFIGURED" }, 503);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace("Bearer ", "");
    const admin = createClient(supabaseUrl, serviceKey);

    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    if (userError || !userData.user) {
      return json({ error: "UNAUTHORIZED" }, 401);
    }
    const user = userData.user;

    const { order_id } = await req.json();
    if (!order_id || typeof order_id !== "string") {
      return json({ error: "ORDER_ID_REQUIRED" }, 400);
    }

    const { data: order, error: orderError } = await admin
      .from("orders")
      .select("id, customer_id, total, payment_method, payment_status")
      .eq("id", order_id)
      .single();

    if (orderError || !order) return json({ error: "ORDER_NOT_FOUND" }, 404);
    if (order.customer_id !== user.id) return json({ error: "FORBIDDEN" }, 403);
    if (order.payment_method !== "paymob") {
      return json({ error: "ORDER_NOT_PAYMOB" }, 400);
    }
    if (order.payment_status === "paid") {
      return json({ error: "ALREADY_PAID" }, 400);
    }

    const { data: profile } = await admin
      .from("profiles")
      .select("full_name, phone")
      .eq("id", user.id)
      .single();

    const fullName = (profile?.full_name ?? "Customer").trim();
    const [firstName, ...rest] = fullName.split(/\s+/);
    const lastName = rest.join(" ") || firstName;

    // special_reference must be unique per intention; suffix allows retries
    // for the same order. The webhook parses the order id back out.
    const specialReference = `${order.id}:${Date.now()}`;

    const intentionRes = await fetch(`${PAYMOB_BASE}/v1/intention/`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Token ${secretKey}`,
      },
      body: JSON.stringify({
        amount: Math.round(Number(order.total) * 100),
        currency: "EGP",
        payment_methods: [Number(integrationId)],
        special_reference: specialReference,
        notification_url: `${supabaseUrl}/functions/v1/paymob-webhook`,
        redirection_url: "https://payment-complete.local/",
        billing_data: {
          first_name: firstName || "NA",
          last_name: lastName || "NA",
          phone_number: profile?.phone ?? "+200000000000",
          email: user.email ?? "na@example.com",
          apartment: "NA",
          floor: "NA",
          street: "NA",
          building: "NA",
          city: "NA",
          state: "NA",
          country: "EG",
        },
        extras: { order_id: order.id },
      }),
    });

    if (!intentionRes.ok) {
      const detail = await intentionRes.text();
      console.error("Paymob intention failed", intentionRes.status, detail);
      return json({ error: "PAYMOB_INTENTION_FAILED" }, 502);
    }

    const intention = await intentionRes.json();
    const clientSecret = intention.client_secret;
    if (!clientSecret) {
      return json({ error: "PAYMOB_NO_CLIENT_SECRET" }, 502);
    }

    await admin
      .from("orders")
      .update({ payment_status: "pending" })
      .eq("id", order.id);

    return json({
      checkout_url:
        `${PAYMOB_BASE}/unifiedcheckout/?publicKey=${publicKey}` +
        `&clientSecret=${clientSecret}`,
      client_secret: clientSecret,
    });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
