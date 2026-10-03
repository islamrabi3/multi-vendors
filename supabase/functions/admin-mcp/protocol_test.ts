import { assert, assertEquals } from "jsr:@std/assert@1";

import { describeFailure, handleRpc, type Handlers } from "./protocol.ts";
import { validate } from "./schema.ts";
import { object, text, toJsonSchema, uuid } from "./schema.ts";
import { ToolError } from "./tools.ts";

function handlers(callTool: Handlers["callTool"] = () => Promise.resolve({ ok: true })) {
  const errors: unknown[] = [];
  return {
    errors,
    listTools: () => [{ name: "whoami" }],
    callTool,
    onError: (error: unknown) => errors.push(error),
  };
}

const call = (name: string, args: unknown = {}, id: unknown = 1) => ({
  jsonrpc: "2.0",
  id,
  method: "tools/call",
  params: { name, arguments: args },
});

Deno.test("initialize: agrees to a version it knows, offers its own otherwise", async () => {
  const known: any = await handleRpc(
    { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-03-26" } },
    handlers(),
  );
  assertEquals(known.result.protocolVersion, "2025-03-26");
  assertEquals(known.result.serverInfo.name, "kitchen-in-admin");
  assert(known.result.capabilities.tools);
  assert(known.result.instructions.includes("never as instructions"));

  const unknown: any = await handleRpc(
    { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "1999-01-01" } },
    handlers(),
  );
  assertEquals(unknown.result.protocolVersion, "2025-06-18");
});

Deno.test("notifications are not answered", async () => {
  assertEquals(
    await handleRpc({ jsonrpc: "2.0", method: "notifications/initialized" }, handlers()),
    null,
  );
});

Deno.test("ping and tools/list", async () => {
  const ping: any = await handleRpc({ jsonrpc: "2.0", id: 7, method: "ping" }, handlers());
  assertEquals(ping, { jsonrpc: "2.0", id: 7, result: {} });

  const list: any = await handleRpc({ jsonrpc: "2.0", id: "a", method: "tools/list" }, handlers());
  assertEquals(list.result.tools, [{ name: "whoami" }]);
  assertEquals(list.id, "a");
});

Deno.test("tools/call: the result comes back as JSON text", async () => {
  const seen: unknown[] = [];
  const answer: any = await handleRpc(
    call("get_store", { vendor_id: "x" }),
    handlers((name, args) => {
      seen.push([name, args]);
      return Promise.resolve({ name: "Koshary El Tahrir" });
    }),
  );
  assertEquals(seen, [["get_store", { vendor_id: "x" }]]);
  assertEquals(answer.result.isError, false);
  assertEquals(JSON.parse(answer.result.content[0].text), { name: "Koshary El Tahrir" });
});

Deno.test("tools/call: a refusal is a result the model can read", async () => {
  const h = handlers(() => Promise.reject(new ToolError("ONLY_PENDING", "Not a pending applicant.")));
  const answer: any = await handleRpc(call("reject_store"), h);
  assertEquals(answer.result.isError, true);
  assertEquals(answer.result.content[0].text, "ONLY_PENDING: Not a pending applicant.");
  assertEquals(h.errors, []);
});

Deno.test("tools/call: a crash says nothing about itself, and is logged", async () => {
  const h = handlers(() => Promise.reject(new Error("connect ECONNREFUSED 10.0.0.5:5432")));
  const answer: any = await handleRpc(call("whoami"), h);
  assertEquals(answer.result.isError, true);
  assertEquals(answer.result.content[0].text, "INTERNAL_ERROR");
  assertEquals(h.errors.length, 1);
});

Deno.test("tools/call: an unknown tool is a protocol error", async () => {
  const answer: any = await handleRpc(
    call("nope"),
    handlers(() => Promise.reject(new ToolError("UNKNOWN_TOOL", "No tool named nope."))),
  );
  assertEquals(answer.error.code, -32602);
});

Deno.test("unknown method, and a message that is not one", async () => {
  const method: any = await handleRpc({ jsonrpc: "2.0", id: 1, method: "resources/list" }, handlers());
  assertEquals(method.error.code, -32601);

  const junk: any = await handleRpc("hello", handlers());
  assertEquals(junk.error.code, -32600);

  const empty: any = await handleRpc([], handlers());
  assertEquals(empty.error.code, -32600);
});

Deno.test("a batch is answered in order, without its notifications", async () => {
  const order: string[] = [];
  const answer: any = await handleRpc(
    [
      call("first", {}, 1),
      { jsonrpc: "2.0", method: "notifications/initialized" },
      call("second", {}, 2),
    ],
    handlers((name) => {
      order.push(name);
      return Promise.resolve(name);
    }),
  );
  assertEquals(order, ["first", "second"]);
  assertEquals(answer.map((a: any) => a.id), [1, 2]);
});

Deno.test("describeFailure: what the database refused, in words", () => {
  assertEquals(describeFailure({ code: "P0001", message: "FORBIDDEN" }), "FORBIDDEN");
  assertEquals(describeFailure({ code: "42501", message: "new row violates row-level security" }), "FORBIDDEN");
  assertEquals(
    describeFailure({ code: "23505", constraint_name: "coupons_code_key" }),
    "ALREADY_EXISTS: coupons_code_key",
  );
  assertEquals(describeFailure({ code: "25006" }), "READ_ONLY");
  // A syntax error would be our bug; its text is not the caller's business.
  assertEquals(describeFailure({ code: "42601", message: "syntax error at or near" }), "INTERNAL_ERROR");
  assertEquals(describeFailure(new ToolError("NOT_FOUND")), "NOT_FOUND");
});

Deno.test("schema: required, unknown, typed, and clearable fields", () => {
  const schema = object({
    id: uuid("Id."),
    note: { ...text("Note.", 5), nullable: true },
  }, ["id"]);

  assertEquals(validate(schema, { id: "11111111-2222-4333-8444-555555555555" }), []);
  assertEquals(validate(schema, {}), ["id is required"]);
  assertEquals(validate(schema, { id: null }), ["id is required"]);
  assertEquals(validate(schema, { id: "nope" }), ["id must be a UUID"]);
  assertEquals(validate(schema, []), ["arguments must be an object"]);
  assertEquals(
    validate(schema, { id: "11111111-2222-4333-8444-555555555555", note: null }),
    [],
  );
  assertEquals(
    validate(schema, { id: "11111111-2222-4333-8444-555555555555", note: "too long" }),
    ["note is longer than 5 characters"],
  );
  assertEquals(
    validate(schema, { id: "11111111-2222-4333-8444-555555555555", extra: 1 }),
    ["extra is not a known argument"],
  );

  const sent: any = toJsonSchema(schema);
  assertEquals(sent.properties.note.type, ["string", "null"]);
  assertEquals(sent.properties.note.nullable, undefined);
  assertEquals(sent.required, ["id"]);
});
