// Settles a Paymob payment from the checkout's redirect, as a backup to the
// webhook.
//
// When the customer finishes paying, Paymob redirects the checkout page to our
// redirection_url with the full transaction in the query string, signed with
// the same HMAC as the webhook. The app forwards those parameters here. If the
// webhook already settled the payment this is a no-op; if the webhook never
// arrived (or failed to reach the database), this is what stops a paid order
// from staying invisible to the restaurant.
//
// Nothing is trusted without the HMAC: the parameters come through the
// customer's device, so a forged "success=true" fails verification.
//
// There is a second way in. A customer who pays and then closes the checkout
// page by hand — before Paymob's own five-second countdown redirects — leaves
// no signed redirect at all, so the app used to have nothing but the webhook
// to go on and reported a failure whenever the webhook was a moment late.
// Called with `inquire: true`, this asks Paymob directly what became of the
// checkout. The answer comes from Paymob's API over our own authenticated
// connection, so it needs no signature to be trustworthy.
//
// Secrets required: PAYMOB_HMAC_SECRET, PAYMOB_SECRET_KEY
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

// The redirect carries the same fields as the webhook, flattened: `order` is
// the Paymob order id and nested source data uses dotted names. Field order is
// defined by Paymob and must not change.
function hmacFieldValues(p: Record<string, string>): string {
  return [
    p["amount_cents"],
    p["created_at"],
    p["currency"],
    p["error_occured"],
    p["has_parent_transaction"],
    p["id"],
    p["integration_id"],
    p["is_3d_secure"],
    p["is_auth"],
    p["is_capture"],
    p["is_refunded"],
    p["is_standalone_payment"],
    p["is_voided"],
    p["order"],
    p["owner"],
    p["pending"],
    p["source_data.pan"],
    p["source_data.sub_type"],
    p["source_data.type"],
    p["success"],
  ].map((v) => `${v ?? ""}`).join("");
}

async function computeHmac(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const hmacSecret = Deno.env.get("PAYMOB_HMAC_SECRET");
    if (!hmacSecret) return json({ error: "PAYMOB_NOT_CONFIGURED" }, 503);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: userData } = await admin.auth.getUser(jwt);
    const user = userData?.user;
    if (!user) return json({ error: "UNAUTHORIZED" }, 401);

    const body = await req.json().catch(() => ({}));
    const reference = `${body.reference ?? ""}`;
    const inquire = body.inquire === true;
    const raw = body.params;
    if (!reference || (!inquire && (!raw || typeof raw !== "object"))) {
      return json({ error: "INVALID_REQUEST" }, 400);
    }
    const params: Record<string, string> = {};
    if (raw && typeof raw === "object") {
      for (const [k, v] of Object.entries(raw)) params[k] = `${v}`;
    }

    // The caller may only confirm their own payment.
    const { data: intent } = await admin
      .from("payment_intents")
      .select("status, user_id, order_id, amount, provider_intention_id")
      .eq("reference", reference)
      .maybeSingle();
    if (!intent) return json({ error: "NOT_FOUND" }, 404);
    if (intent.user_id !== user.id) return json({ error: "FORBIDDEN" }, 403);
    if (intent.status !== "pending") return json({ status: intent.status });

    // Settles the intent and records the payment. Both paths end here; the
    // difference between them is only where the verdict came from.
    const settle = async (
      success: boolean,
      transactionId: string | null,
      amountCents: number,
      failureReason: string | null,
      source: string,
      payload: Record<string, unknown>,
    ) => {
      let outcome: unknown = null;
      let lastError: unknown = null;
      for (let attempt = 0; attempt < 4; attempt++) {
        const { data, error } = await admin.rpc("settle_payment_intent", {
          p_reference: reference,
          p_success: success,
          p_transaction_id: transactionId,
          p_failure_reason: success ? null : failureReason,
        });
        if (!error) {
          outcome = data;
          lastError = null;
          break;
        }
        lastError = error;
        await sleep(700 * (attempt + 1));
      }
      if (lastError) {
        console.error("settle failed", reference, lastError);
        return null;
      }

      const { count: already } = await admin
        .from("payments")
        .select("id", { count: "exact", head: true })
        .eq("provider_transaction_id", transactionId ?? "");
      if (
        intent.order_id &&
        !already &&
        (outcome === "paid" || outcome === "failed")
      ) {
        await admin.from("payments").insert({
          order_id: intent.order_id,
          provider: "paymob",
          amount: amountCents / 100,
          status: outcome,
          provider_transaction_id: transactionId,
          provider_order_id: `${payload["order"] ?? ""}` || null,
          raw_payload: { source, ...payload },
        });
      }
      return outcome;
    };

    // ---- Asking Paymob directly -------------------------------------------
    if (inquire) {
      const secretKey = Deno.env.get("PAYMOB_SECRET_KEY");
      const intentionId = intent.provider_intention_id;
      if (!secretKey) return json({ error: "PAYMOB_NOT_CONFIGURED" }, 503);
      // Checkouts opened before this id was recorded can only be settled by
      // the webhook; saying "pending" leaves them to it.
      if (!intentionId) return json({ status: "pending", reason: "NO_INTENTION_ID" });

      const inquiry = await fetch(`${PAYMOB_BASE}/v1/intention/${intentionId}`, {
        headers: { Authorization: `Token ${secretKey}` },
      });
      if (!inquiry.ok) {
        console.error("intention inquiry failed", inquiry.status, reference);
        return json({ status: "pending", reason: "INQUIRY_FAILED" });
      }
      const data = await inquiry.json();
      const transactions = Array.isArray(data?.transactions)
        ? data.transactions
        : [];
      // The last attempt is the one that counts: a customer who is declined
      // and pays again on the same checkout has two.
      const txn = transactions[transactions.length - 1];
      if (!txn) return json({ status: "pending", reason: "NO_TRANSACTION" });
      if (txn.pending === true) return json({ status: "pending" });

      const success = txn.success === true;
      const amountCents = Number(txn.amount_cents ?? 0);
      if (success && amountCents !== Math.round(Number(intent.amount) * 100)) {
        console.error("inquiry amount mismatch", reference, amountCents);
        return json({ error: "AMOUNT_MISMATCH" }, 400);
      }

      const outcome = await settle(
        success,
        txn.id == null ? null : `${txn.id}`,
        amountCents,
        `${txn.data?.message ?? "declined"}`,
        "inquiry",
        { order: txn.order?.id ?? txn.order ?? null, transaction: txn },
      );
      if (outcome === null) return json({ error: "SETTLEMENT_ERROR" }, 500);
      console.log("settled from inquiry", reference, outcome);
      return json({ status: outcome });
    }

    const received = params["hmac"];
    if (!received) return json({ status: "pending", reason: "NO_SIGNATURE" });
    const expected = await computeHmac(hmacFieldValues(params), hmacSecret);
    if (expected !== received) {
      console.error("redirect HMAC mismatch", reference, params["id"]);
      return json({ error: "INVALID_SIGNATURE" }, 401);
    }

    // The signed transaction must be for this very checkout.
    const signedReference = params["merchant_order_id"];
    if (signedReference && signedReference !== reference) {
      return json({ error: "REFERENCE_MISMATCH" }, 400);
    }
    if (params["pending"] === "true") return json({ status: "pending" });

    const success = params["success"] === "true";
    if (
      success &&
      Number(params["amount_cents"]) !== Math.round(Number(intent.amount) * 100)
    ) {
      console.error("redirect amount mismatch", reference, params["amount_cents"]);
      return json({ error: "AMOUNT_MISMATCH" }, 400);
    }
    const outcome = await settle(
      success,
      params["id"] ?? null,
      Number(params["amount_cents"] ?? 0),
      `${params["data.message"] ?? "declined"}`,
      "redirect",
      params,
    );
    if (outcome === null) return json({ error: "SETTLEMENT_ERROR" }, 500);

    console.log("settled from redirect", reference, outcome);
    return json({ status: outcome });
  } catch (error) {
    console.error(error);
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
