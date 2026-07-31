// Paymob "transaction processed" webhook. Public endpoint (verify_jwt off);
// authenticity is established by the HMAC-SHA512 signature Paymob sends as a
// query parameter, computed over a fixed, lexicographically-ordered field list.
//
// This is the only place a card payment is allowed to settle: it hands the
// transaction to settle_payment_intent(), which credits a wallet or marks an
// order paid, exactly once per reference.
//
// Secrets required: PAYMOB_HMAC_SECRET
import { createClient } from "npm:@supabase/supabase-js@2";

// deno-lint-ignore no-explicit-any
function hmacFieldValues(obj: any): string {
  // Field order is defined by Paymob's docs and must not change.
  const values = [
    obj.amount_cents,
    obj.created_at,
    obj.currency,
    obj.error_occured,
    obj.has_parent_transaction,
    obj.id,
    obj.integration_id,
    obj.is_3d_secure,
    obj.is_auth,
    obj.is_capture,
    obj.is_refunded,
    obj.is_standalone_payment,
    obj.is_voided,
    obj.order?.id,
    obj.owner,
    obj.pending,
    obj.source_data?.pan,
    obj.source_data?.sub_type,
    obj.source_data?.type,
    obj.success,
  ];
  return values.map((v) => `${v}`).join("");
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

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const hmacSecret = Deno.env.get("PAYMOB_HMAC_SECRET");
    if (!hmacSecret) {
      return new Response("PAYMOB_NOT_CONFIGURED", { status: 503 });
    }

    const url = new URL(req.url);
    const receivedHmac = url.searchParams.get("hmac");
    const payload = await req.json();
    const tx = payload.obj;

    if (!receivedHmac || !tx) {
      return new Response("Bad request", { status: 400 });
    }

    const expectedHmac = await computeHmac(hmacFieldValues(tx), hmacSecret);
    if (expectedHmac !== receivedHmac) {
      console.error("HMAC mismatch for transaction", tx.id);
      return new Response("Invalid signature", { status: 401 });
    }

    // special_reference comes back as merchant_order_id.
    const reference: string = tx.order?.merchant_order_id ?? "";
    if (!reference) {
      console.error("No merchant_order_id on transaction", tx.id);
      return new Response("ok", { status: 200 });
    }

    // A pending transaction is not an outcome — wait for the final callback.
    if (tx.pending === true) {
      return new Response("ok", { status: 200 });
    }

    const success = tx.success === true;
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: outcome, error: settleError } = await admin.rpc(
      "settle_payment_intent",
      {
        p_reference: reference,
        p_success: success,
        p_transaction_id: `${tx.id}`,
        p_failure_reason: success
          ? null
          : `${tx.data?.message ?? tx.error_occured ?? "declined"}`,
      },
    );

    if (settleError) {
      // 500 makes Paymob retry rather than silently dropping the payment.
      console.error("settle_payment_intent failed", reference, settleError);
      return new Response("Settlement error", { status: 500 });
    }

    // Audit trail. Only order payments belong in `payments` (it FKs orders).
    if (reference.startsWith("order-")) {
      const { data: intent } = await admin
        .from("payment_intents")
        .select("order_id")
        .eq("reference", reference)
        .maybeSingle();

      if (intent?.order_id) {
        await admin.from("payments").insert({
          order_id: intent.order_id,
          provider: "paymob",
          amount: Number(tx.amount_cents ?? 0) / 100,
          status: success ? "paid" : "failed",
          provider_transaction_id: `${tx.id}`,
          provider_order_id: `${tx.order?.id ?? ""}`,
          raw_payload: tx,
        });
      }
    }

    console.log("settled", reference, outcome);
    return new Response("ok", { status: 200 });
  } catch (error) {
    console.error(error);
    return new Response("Internal error", { status: 500 });
  }
});
