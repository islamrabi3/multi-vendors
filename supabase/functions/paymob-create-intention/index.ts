// Creates a Paymob payment intention and returns the unified checkout URL.
//
// Two kinds of payment:
//   { order_id: "<uuid>" }            -> pay for an order; amount read from the
//                                        order row, never from the client
//   { kind: "topup", amount: 100 }    -> wallet top-up
//
// Caller must be signed in (JWT verified by the platform, re-checked here).
// The returned `reference` is Paymob's special_reference; the app watches the
// matching payment_intents row to learn whether the payment settled.
//
// Either kind may also carry { channel: "card" | "wallet" }. Both produce the
// same unified-checkout URL and settle through the same webhook — the only
// difference is which Paymob integration the intention is opened against, and
// so which methods Paymob offers on its hosted page. "wallet" here means an
// Egyptian mobile wallet (Vodafone Cash, Etisalat, Orange); it is not this
// app's own stored balance, which is paid from the ledger and never reaches
// the gateway at all.
//
// Secrets required:
//   PAYMOB_SECRET_KEY, PAYMOB_PUBLIC_KEY, PAYMOB_INTEGRATION_ID
// Optional:
//   PAYMOB_WALLET_INTEGRATION_ID — without it a wallet request falls back to
//   the card integration rather than failing, so a customer is never left
//   unable to pay because a secret has not been set yet.
import { createClient } from "npm:@supabase/supabase-js@2";

const PAYMOB_BASE = "https://accept.paymob.com";
const REDIRECT_URL = "https://payment-complete.local/";

const TOPUP_MIN = 10;
const TOPUP_MAX = 20000;

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
    const walletIntegrationId = Deno.env.get("PAYMOB_WALLET_INTEGRATION_ID");

    if (!secretKey || !publicKey || !integrationId) {
      return json({ error: "PAYMOB_NOT_CONFIGURED" }, 503);
    }

    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const admin = createClient(supabaseUrl, serviceKey);

    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    if (userError || !userData.user) {
      return json({ error: "UNAUTHORIZED" }, 401);
    }
    const user = userData.user;

    const body = await req.json().catch(() => ({}));
    const kind = body.kind === "topup" ? "topup" : "order";

    // Anything other than an explicit "wallet" is a card, so an old client
    // that sends no channel at all keeps its current behaviour exactly.
    const channel = body.channel === "wallet" ? "wallet" : "card";
    const chosenIntegrationId = channel === "wallet"
      ? (walletIntegrationId ?? integrationId)
      : integrationId;

    // amountEgp drives the intent row; amountCents is what Paymob is told.
    let amountEgp = 0;
    let orderId: string | null = null;
    let reference = "";

    if (kind === "topup") {
      amountEgp = Number(body.amount);
      if (!Number.isFinite(amountEgp) || amountEgp < TOPUP_MIN || amountEgp > TOPUP_MAX) {
        return json({ error: "INVALID_TOPUP_AMOUNT" }, 400);
      }
      amountEgp = Math.round(amountEgp * 100) / 100;
      reference = `topup-${crypto.randomUUID()}`;
    } else {
      const requestedOrderId = body.order_id;
      if (!requestedOrderId || typeof requestedOrderId !== "string") {
        return json({ error: "ORDER_ID_REQUIRED" }, 400);
      }

      const { data: order, error: orderError } = await admin
        .from("orders")
        .select("id, customer_id, total, payment_method, payment_status, status")
        .eq("id", requestedOrderId)
        .single();

      if (orderError || !order) return json({ error: "ORDER_NOT_FOUND" }, 404);
      if (order.customer_id !== user.id) return json({ error: "FORBIDDEN" }, 403);
      if (order.payment_method !== "paymob") {
        return json({ error: "ORDER_NOT_PAYMOB" }, 400);
      }
      if (order.payment_status === "paid") {
        return json({ error: "ALREADY_PAID" }, 400);
      }

      amountEgp = Number(order.total);
      orderId = order.id;
      reference = `order-${order.id}-${crypto.randomUUID().slice(0, 8)}`;
    }

    const amountCents = Math.round(amountEgp * 100);

    const { data: profile } = await admin
      .from("profiles")
      .select("full_name, phone")
      .eq("id", user.id)
      .single();

    const fullName = (profile?.full_name ?? "Customer").trim();
    const [firstName, ...rest] = fullName.split(/\s+/);
    const lastName = rest.join(" ") || firstName;

    const intentionRes = await fetch(`${PAYMOB_BASE}/v1/intention/`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Token ${secretKey}`,
      },
      body: JSON.stringify({
        amount: amountCents,
        currency: "EGP",
        payment_methods: [Number(chosenIntegrationId)],
        special_reference: reference,
        notification_url: `${supabaseUrl}/functions/v1/paymob-webhook`,
        redirection_url: REDIRECT_URL,
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
        extras: { kind, channel, order_id: orderId, user_id: user.id },
      }),
    });

    if (!intentionRes.ok) {
      const detail = await intentionRes.text();
      console.error("Paymob intention failed", intentionRes.status, detail);
      return json({ error: "PAYMOB_INTENTION_FAILED", detail }, 502);
    }

    const intention = await intentionRes.json();
    const clientSecret = intention.client_secret;
    if (!clientSecret) {
      return json({ error: "PAYMOB_NO_CLIENT_SECRET" }, 502);
    }

    // Recorded only after Paymob accepted the intention, so a pending intent
    // row always corresponds to a checkout the customer can actually reach.
    const { error: intentError } = await admin.rpc("open_payment_intent", {
      p_user_id: user.id,
      p_kind: kind,
      p_reference: reference,
      p_amount: amountEgp,
      p_order_id: orderId,
      // The order row cannot carry this — card and mobile wallet are both
      // payment_method 'paymob' there, and correctly so. Recording it on the
      // intent is what lets the admin money screen tell the two apart.
      p_channel: channel,
    });

    if (intentError) {
      console.error("open_payment_intent failed", intentError);
      return json({ error: "INTENT_RECORD_FAILED" }, 500);
    }

    return json({
      checkout_url:
        `${PAYMOB_BASE}/unifiedcheckout/?publicKey=${publicKey}` +
        `&clientSecret=${clientSecret}`,
      reference,
      amount: amountEgp,
    });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
