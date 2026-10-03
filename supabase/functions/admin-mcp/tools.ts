// What Claude can do in the admin console, one tool per job.
//
// Every tool runs inside a transaction that has already been switched to the
// admin who owns the key (see index.ts), so `auth.uid()`, `has_permission()`
// and every row policy answer exactly as they would for that admin at the
// dashboard. Nothing here decides who may do what; it only asks the database,
// which already knows.
//
// Phase 1 is the day-to-day console: looking things up, answering people,
// approving applicants, and the catalogue and marketing upkeep. Anything that
// moves money or takes a live account off the platform is deliberately absent.
import {
  amount,
  clearable,
  count,
  flag,
  limit,
  object,
  type ObjectSchema,
  offset,
  oneOf,
  text,
  toJsonSchema,
  uuid,
  validate,
  when,
} from "./schema.ts";

/// The one thing a tool needs from the database: run a statement, get back
/// the first column of the first row. Every query here returns JSON built by
/// Postgres, so numbers stay numbers and timestamps arrive already formatted.
export interface Db {
  json<T = unknown>(text: string, params?: unknown[]): Promise<T | null>;
}

export interface Caller {
  adminId: string;
  adminName: string;
  tokenId: string;
  tokenName: string;
}

/// A refusal the model should read and act on, as opposed to a crash.
export class ToolError extends Error {
  constructor(public code: string, message?: string) {
    super(message ?? code);
  }
}

/// The one thing a tool cannot do as the admin: make or remove a login. Logins
/// live in auth.users, which only the Auth admin API may write, so this is
/// handed in from outside and used by `create_store` alone — after the
/// permission check, never before it.
export interface Accounts {
  createLogin(input: {
    email: string;
    password: string;
    fullName: string;
    phone: string | null;
    username: string | null;
    role: "vendor";
  }): Promise<string>;
  deleteLogin(userId: string): Promise<void>;
}

export interface Tool {
  name: string;
  title: string;
  description: string;
  /// The admin needs any one of these. Omitted: any admin may call it.
  permission?: readonly string[];
  readOnly: boolean;
  input: ObjectSchema;
  run(
    db: Db,
    args: Record<string, any>,
    caller: Caller,
    accounts?: Accounts,
  ): Promise<unknown>;
}

// ---------------------------------------------------------------------------
// Query helpers
// ---------------------------------------------------------------------------

const many = (db: Db, inner: string, params: unknown[] = []) =>
  db.json(
    `select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (${inner}) t`,
    params,
  );

const one = (db: Db, inner: string, params: unknown[] = []) =>
  db.json(`select to_jsonb(t) from (${inner}) t limit 1`, params);

/// Collects conditions and their values together, so a placeholder can never
/// be numbered apart from the value it stands for.
class Where {
  readonly params: unknown[] = [];
  private readonly parts: string[] = [];

  bind(value: unknown, cast: string): string {
    this.params.push(value);
    return `$${this.params.length}::${cast}`;
  }

  add(condition: string): void {
    this.parts.push(condition);
  }

  toString(): string {
    return this.parts.length ? `where ${this.parts.join(" and ")}` : "";
  }
}

/// A search term as an ILIKE pattern, with the wildcards a person might type
/// by accident made literal.
const like = (term: string) =>
  `%${term.trim().replace(/[\\%_]/g, (c) => `\\${c}`)}%`;

const page = (w: Where, args: Record<string, any>) =>
  `limit ${w.bind(args.limit ?? 25, "integer")} offset ${
    w.bind(args.offset ?? 0, "integer")
  }`;

/// Argument name → the Postgres type it is written as. The argument and the
/// column share a name, and only names listed here ever reach the SQL text.
type Columns = Record<string, string>;

function given(columns: Columns, args: Record<string, any>) {
  return Object.keys(columns).filter((name) => args[name] !== undefined);
}

async function insertRow(
  db: Db,
  table: string,
  columns: Columns,
  args: Record<string, any>,
): Promise<Record<string, any>> {
  const names = given(columns, args);
  const values = names.map((name, i) => `$${i + 1}::${columns[name]}`);
  const created = await db.json<Record<string, any>>(
    `with r as (insert into public.${table} (${names.join(", ")}) ` +
      `values (${values.join(", ")}) returning *) select to_jsonb(r) from r`,
    names.map((name) => args[name]),
  );
  if (!created) throw new ToolError("FORBIDDEN");
  return created;
}

async function updateRow(
  db: Db,
  table: string,
  columns: Columns,
  id: string,
  args: Record<string, any>,
): Promise<Record<string, any>> {
  const names = given(columns, args);
  if (names.length === 0) {
    throw new ToolError("NOTHING_TO_UPDATE", "No field to change was given.");
  }
  const sets = names.map((name, i) => `${name} = $${i + 2}::${columns[name]}`);
  const updated = await db.json<Record<string, any>>(
    `with r as (update public.${table} set ${sets.join(", ")} ` +
      `where id = $1::uuid returning *) select to_jsonb(r) from r`,
    [id, ...names.map((name) => args[name])],
  );
  if (!updated) throw new ToolError("NOT_FOUND", `No ${table} row ${id}.`);
  return updated;
}

/// Leaves a line in the admin log for a write that went straight to a table.
/// The RPCs log themselves; these would otherwise leave no trace.
const audit = (
  db: Db,
  action: string,
  targetType: string,
  targetId: string | null,
  detail: Record<string, unknown> = {},
) =>
  db.json(
    "select public.admin_mcp_log($1::text, $2::text, $3::uuid, $4::text::jsonb)",
    [action, targetType, targetId, JSON.stringify(detail)],
  );

const range = {
  from: when("Start of the period (inclusive). Omit for all time."),
  to: when("End of the period (exclusive). Omit for up to now."),
};

// ---------------------------------------------------------------------------
// Shared selects
// ---------------------------------------------------------------------------

const ORDER_STATUSES = [
  "pending",
  "accepted",
  "preparing",
  "ready_for_pickup",
  "out_for_delivery",
  "delivered",
  "cancelled",
  "rejected",
] as const;

const APPROVAL = ["pending", "active", "suspended"] as const;

const ORDER_ROW = `
  select o.id, o.order_number, o.status, o.order_flow, o.order_type,
         o.payment_method, o.payment_status, o.subtotal, o.delivery_fee,
         o.service_fee, o.discount, o.total, o.created_at, o.scheduled_at,
         o.delivered_at, o.cancelled_at, o.rejection_reason,
         o.vendor_id, v.name as vendor_name,
         o.customer_id, c.full_name as customer_name, c.phone as customer_phone,
         o.driver_id, d.full_name as driver_name
  from public.orders o
  left join public.vendors v on v.id = o.vendor_id
  left join public.profiles c on c.id = o.customer_id
  left join public.profiles d on d.id = o.driver_id`;

const STORE_ROW = `
  select v.id, v.name, v.approval_status, v.is_active, v.is_open, v.is_busy,
         v.order_flow, v.category_id, v.phone, v.address_text, v.rating_avg,
         v.rating_count, v.delivery_fee, v.min_order_amount, v.billing_model,
         v.commission_rate, v.is_recommended, v.created_at,
         v.owner_id, p.full_name as owner_name, p.phone as owner_phone
  from public.vendors v
  left join public.profiles p on p.id = v.owner_id`;

const DRIVER_ROW = `
  select d.id, p.full_name, p.phone, d.vehicle_type, d.approval_status,
         d.is_online, d.rating_avg, d.rating_count, d.approved_at,
         d.rejection_reason, d.location_updated_at, p.is_blocked,
         p.created_at as joined_at,
         (d.id_card_url is not null and d.license_url is not null)
           as documents_uploaded
  from public.drivers d
  join public.profiles p on p.id = d.id`;

const COMPLAINT_ROW = `
  select r.id, r.subject, r.description, r.status, r.created_at,
         r.last_message_at, r.last_message_from_admin,
         r.user_id, p.full_name as customer_name, p.phone as customer_phone,
         r.order_id, o.order_number, r.vendor_id, v.name as vendor_name
  from public.customer_reports r
  left join public.profiles p on p.id = r.user_id
  left join public.orders o on o.id = r.order_id
  left join public.vendors v on v.id = r.vendor_id`;

const THREAD_ROW = `
  select t.id, t.subject, t.status, t.created_at, t.last_message_at,
         t.resolved_at, t.user_id, p.full_name as user_name,
         p.phone as user_phone, p.role as user_role,
         (select jsonb_build_object(
                   'message', m.message,
                   'is_from_admin', m.is_from_admin,
                   'created_at', m.created_at)
          from public.support_messages m
          where m.thread_id = t.id
          order by m.created_at desc limit 1) as last_message
  from public.support_threads t
  left join public.profiles p on p.id = t.user_id`;

// ---------------------------------------------------------------------------
// Column lists for the tables written to directly
// ---------------------------------------------------------------------------

const COUPON_COLUMNS: Columns = {
  code: "text",
  discount_type: "public.discount_type",
  value: "numeric",
  min_order_amount: "numeric",
  max_discount: "numeric",
  starts_at: "timestamptz",
  expires_at: "timestamptz",
  usage_limit: "integer",
  per_user_limit: "integer",
  first_order_only: "boolean",
  is_public: "boolean",
  is_active: "boolean",
  title: "text",
  title_ar: "text",
  vendor_id: "uuid",
  funded_by: "text",
};

const couponFields = {
  code: text("The code customers type. Stored in capitals.", 40),
  discount_type: oneOf(
    ["percentage", "fixed", "free_delivery"],
    "percentage: value is a percent. fixed: value is an amount of money. " +
      "free_delivery: waives the delivery fee, value is ignored.",
  ),
  value: amount("Percent or amount, depending on discount_type."),
  min_order_amount: amount("Smallest order subtotal the code applies to."),
  max_discount: clearable(amount("Cap on a percentage discount.")),
  starts_at: clearable(when("When the code starts working.")),
  expires_at: clearable(when("When the code stops working.")),
  usage_limit: clearable(count("Total uses across all customers.", 1)),
  per_user_limit: clearable(count("Uses per customer. null = unlimited.", 1)),
  first_order_only: flag("Only for a customer's first order."),
  is_public: flag("Shown to customers in the app rather than shared by hand."),
  is_active: flag("Whether the code can be used."),
  title: clearable(text("Customer-facing title (English).", 120)),
  title_ar: clearable(text("Customer-facing title (Arabic).", 120)),
  vendor_id: clearable(uuid("Limit the code to one store. null = every store.")),
  funded_by: oneOf(
    ["platform", "vendor"],
    "Who pays for the discount. Only a store-scoped code may be 'vendor'.",
  ),
};

const AD_COLUMNS: Columns = {
  image_url: "text",
  title: "text",
  subtitle: "text",
  banner_type: "text",
  placement: "text",
  media_type: "text",
  video_url: "text",
  poster_url: "text",
  vendor_id: "uuid",
  code: "text",
  link_url: "text",
  cta_label: "text",
  advertiser: "text",
  audience: "text",
  starts_at: "timestamptz",
  ends_at: "timestamptz",
  sort_order: "integer",
  is_active: "boolean",
  dismissible: "boolean",
  dismiss_after_seconds: "integer",
  frequency: "text",
};

const adFields = {
  image_url: text("Public URL of the image. Must already be hosted.", 1000),
  title: clearable(text("Headline.", 120)),
  subtitle: clearable(text("Second line.", 200)),
  banner_type: oneOf(
    ["coupon", "vendor", "event"],
    "coupon: promotes a code. vendor: opens a store. event: opens link_url.",
  ),
  placement: oneOf(
    [
      "home_carousel",
      "home_inline",
      "vendor_top",
      "cart",
      "order_tracking",
      "interstitial",
      "splash",
    ],
    "Where in the customer app the ad appears.",
  ),
  media_type: oneOf(["image", "video"], "What the ad shows."),
  video_url: clearable(text("Public URL of the video, for media_type video.", 1000)),
  poster_url: clearable(text("Still shown before a video plays.", 1000)),
  vendor_id: clearable(uuid("Store the ad opens, for banner_type vendor.")),
  code: clearable(text("Coupon code the ad promotes, for banner_type coupon.", 40)),
  link_url: clearable(text("Where the ad leads, for banner_type event.", 1000)),
  cta_label: clearable(text("Button text.", 40)),
  advertiser: clearable(text("Who paid for the ad.", 120)),
  audience: oneOf(
    ["all", "new_customers", "returning_customers"],
    "Which customers see it.",
  ),
  starts_at: clearable(when("When the ad starts showing.")),
  ends_at: clearable(when("When the ad stops showing.")),
  sort_order: count("Position among ads in the same placement."),
  is_active: flag("Whether the ad is shown."),
  dismissible: flag("Whether the customer can close it."),
  dismiss_after_seconds: count("Seconds before it can be closed.", 0, 15),
  frequency: oneOf(
    ["once", "daily", "every_session"],
    "How often one customer sees it.",
  ),
};

const STORE_COLUMNS: Columns = {
  owner_id: "uuid",
  name: "text",
  description: "text",
  category_id: "uuid",
  phone: "text",
  address_text: "text",
  lat: "double precision",
  lng: "double precision",
  min_order_amount: "numeric",
  avg_prep_minutes: "integer",
  delivery_fee: "numeric",
  delivery_radius_km: "double precision",
  billing_model: "text",
  commission_rate: "numeric",
  subscription_fee: "numeric",
  logo_url: "text",
  cover_url: "text",
  approval_status: "text",
  is_open: "boolean",
};

// The same shape the signup form accepts.
const EMAIL =
  /^[^\s@]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/;
const USERNAME = /^[A-Za-z0-9._]{3,20}$/;

const CATEGORY_COLUMNS: Columns = {
  name: "text",
  name_ar: "text",
  parent_id: "uuid",
  image_url: "text",
  sort_order: "integer",
  is_active: "boolean",
  is_coming_soon: "boolean",
};

const categoryFields = {
  name: text("Name in English.", 80),
  name_ar: clearable(text("Name in Arabic.", 80)),
  parent_id: clearable(uuid("Parent category, for a sub-category.")),
  image_url: clearable(text("Public URL of the category image.", 1000)),
  sort_order: count("Position in the list."),
  is_active: flag("Whether customers see it."),
  is_coming_soon: flag("Shown as coming soon instead of opening."),
};

const AREA_COLUMNS: Columns = {
  name: "text",
  name_ar: "text",
  lat: "double precision",
  lng: "double precision",
  radius_km: "numeric",
  is_active: "boolean",
};

const areaFields = {
  name: text("Name in English.", 80),
  name_ar: clearable(text("Name in Arabic.", 80)),
  lat: { type: "number", minimum: -90, maximum: 90, description: "Centre latitude." },
  lng: { type: "number", minimum: -180, maximum: 180, description: "Centre longitude." },
  radius_km: {
    type: "number",
    minimum: 0.1,
    maximum: 300,
    description: "Radius served, in kilometres.",
  },
  is_active: flag("Whether orders are accepted inside it."),
} as const;

// ---------------------------------------------------------------------------
// Approvals
// ---------------------------------------------------------------------------

/// Approving and turning down applicants is phase 1. Suspending somebody who
/// is already trading is a different decision with money attached, and stays
/// at the dashboard until it has its own preview-and-confirm step.
async function decide(
  db: Db,
  kind: "vendor" | "driver",
  id: string,
  approve: boolean,
  reason?: string,
) {
  const table = kind === "vendor" ? "vendors" : "drivers";
  const current = await db.json<string>(
    `select approval_status from public.${table} where id = $1::uuid`,
    [id],
  );
  if (!current) throw new ToolError("NOT_FOUND", `No ${kind} ${id}.`);
  if (!approve && current !== "pending") {
    throw new ToolError(
      "ONLY_PENDING",
      `This ${kind} is '${current}', not a pending applicant. Suspending an ` +
        "approved account is not available through Claude; use the dashboard.",
    );
  }
  if (approve && current === "active") {
    throw new ToolError("ALREADY_ACTIVE", `This ${kind} is already approved.`);
  }
  // The dashboard has no separate "rejected" state either: an applicant who
  // is turned down is suspended, with the reason kept for a driver.
  const status = approve ? "active" : "suspended";
  if (kind === "vendor") {
    await db.json(
      "select public.admin_set_vendor_status($1::uuid, $2::text)",
      [id, status],
    );
    return one(db, `${STORE_ROW} where v.id = $1::uuid`, [id]);
  }
  await db.json(
    "select public.admin_set_driver_status($1::uuid, $2::text, $3::text)",
    [id, status, reason ?? null],
  );
  return one(db, `${DRIVER_ROW} where d.id = $1::uuid`, [id]);
}

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

export const tools: readonly Tool[] = [
  {
    name: "whoami",
    title: "Who am I acting as",
    description:
      "The admin this key belongs to and what they are allowed to do. " +
      "Call it first when unsure whether an action is permitted.",
    readOnly: true,
    input: object({}),
    run: (db, _args, caller) =>
      db.json(
        `select jsonb_build_object(
           'admin_id', p.id,
           'name', p.full_name,
           'role', coalesce(r.name, 'Full access'),
           'permissions', to_jsonb(public.my_permissions()),
           'key_name', $1::text)
         from public.profiles p
         left join public.admin_roles r on r.id = p.admin_role_id
         where p.id = auth.uid()`,
        [caller.tokenName],
      ),
  },
  {
    name: "dashboard_summary",
    title: "Dashboard summary",
    description:
      "Today's headline numbers and what is waiting on an admin right now: " +
      "pending stores and drivers, open complaints, unanswered support " +
      "chats, orders needing attention.",
    readOnly: true,
    input: object({}),
    run: (db) =>
      db.json(
        `select jsonb_build_object(
           'stats', public.admin_dashboard_stats(),
           'waiting', public.admin_action_counts())`,
      ),
  },

  // -- Orders ---------------------------------------------------------------
  {
    name: "search_orders",
    title: "Search orders",
    description:
      "Find orders, newest first. Filter by status, store, driver, customer, " +
      "payment or date, or search by order number, customer name or phone, " +
      "or store name. needs_attention returns the orders the dashboard flags: " +
      "open for over 30 minutes, or waiting for an admin to accept.",
    permission: ["orders.view"],
    readOnly: true,
    input: object({
      query: text("Order number, customer name or phone, or store name.", 100),
      status: oneOf(ORDER_STATUSES, "Only orders in this status."),
      order_flow: oneOf(
        ["vendor", "platform", "direct"],
        "Only orders run this way.",
      ),
      payment_status: oneOf(
        ["unpaid", "pending", "paid", "failed", "refunded"],
        "Only orders with this payment status.",
      ),
      vendor_id: uuid("Only this store's orders."),
      driver_id: uuid("Only this driver's orders."),
      customer_id: uuid("Only this customer's orders."),
      needs_attention: flag("Only orders the dashboard flags as needing an admin."),
      ...range,
      limit,
      offset,
    }),
    run: (db, a) => {
      const w = new Where();
      if (a.query) {
        const q = w.bind(like(a.query), "text");
        w.add(
          `(o.order_number ilike ${q} or c.full_name ilike ${q} ` +
            `or c.phone ilike ${q} or v.name ilike ${q})`,
        );
      }
      if (a.status) w.add(`o.status = ${w.bind(a.status, "public.order_status")}`);
      if (a.order_flow) w.add(`o.order_flow = ${w.bind(a.order_flow, "text")}`);
      if (a.payment_status) {
        w.add(
          `o.payment_status = ${w.bind(a.payment_status, "public.payment_status")}`,
        );
      }
      if (a.vendor_id) w.add(`o.vendor_id = ${w.bind(a.vendor_id, "uuid")}`);
      if (a.driver_id) w.add(`o.driver_id = ${w.bind(a.driver_id, "uuid")}`);
      if (a.customer_id) w.add(`o.customer_id = ${w.bind(a.customer_id, "uuid")}`);
      if (a.from) w.add(`o.created_at >= ${w.bind(a.from, "timestamptz")}`);
      if (a.to) w.add(`o.created_at < ${w.bind(a.to, "timestamptz")}`);
      if (a.needs_attention) {
        // The same rule as admin_action_counts, so the list and the badge
        // never disagree about what "needs attention" means.
        w.add(
          `o.status in ('pending', 'accepted', 'preparing', 'ready_for_pickup')
           and (o.payment_method <> 'paymob' or o.payment_status = 'paid')
           and (o.created_at < now() - interval '30 minutes'
                or (o.order_flow = 'platform' and o.status = 'pending'
                    and o.released_at is not null))`,
        );
      }
      return many(
        db,
        `${ORDER_ROW} ${w} order by o.created_at desc ${page(w, a)}`,
        w.params,
      );
    },
  },
  {
    name: "get_order",
    title: "Order details",
    description:
      "Everything about one order: items, amounts, payment, the store, the " +
      "customer, the driver and each status change. Give either the order's " +
      "id or its order number.",
    permission: ["orders.view"],
    readOnly: true,
    input: object({
      order_id: uuid("The order's id."),
      order_number: text("The order number shown to customers.", 40),
    }),
    run: async (db, a) => {
      if (!a.order_id && !a.order_number) {
        throw new ToolError("INVALID_ARGUMENTS", "Give order_id or order_number.");
      }
      const match = a.order_id
        ? "o.id = $1::uuid"
        : "o.order_number = $1::text";
      // The handover codes are what prove a delivery happened; they are for
      // the customer and the rider, not for a transcript.
      const order = await db.json(
        `select (to_jsonb(o) - 'delivery_otp' - 'pickup_code') || jsonb_build_object(
           'vendor', (select jsonb_build_object(
                        'id', v.id, 'name', v.name, 'phone', v.phone)
                      from public.vendors v where v.id = o.vendor_id),
           'customer', (select jsonb_build_object(
                          'id', p.id, 'full_name', p.full_name, 'phone', p.phone)
                        from public.profiles p where p.id = o.customer_id),
           'driver', (select jsonb_build_object(
                        'id', p.id, 'full_name', p.full_name, 'phone', p.phone)
                      from public.profiles p where p.id = o.driver_id),
           'items', (select coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb)
                     from public.order_items i where i.order_id = o.id),
           'status_history', (
             select coalesce(jsonb_agg(jsonb_build_object(
                      'status', h.status, 'at', h.created_at,
                      'changed_by', h.changed_by) order by h.created_at),
                    '[]'::jsonb)
             from public.order_status_history h where h.order_id = o.id))
         from public.orders o where ${match}`,
        [a.order_id ?? a.order_number],
      );
      if (!order) throw new ToolError("NOT_FOUND", "No such order.");
      return order;
    },
  },

  // -- Stores ---------------------------------------------------------------
  {
    name: "list_stores",
    title: "List stores",
    description:
      "Stores on the platform, newest first, with their approval status and " +
      "owner. Filter by status or category, or search by name.",
    permission: ["vendors.view"],
    readOnly: true,
    input: object({
      query: text("Part of the store's name.", 100),
      status: oneOf(APPROVAL, "Only stores with this approval status."),
      category_id: uuid("Only stores in this category."),
      limit,
      offset,
    }),
    run: (db, a) => {
      const w = new Where();
      if (a.query) w.add(`v.name ilike ${w.bind(like(a.query), "text")}`);
      if (a.status) w.add(`v.approval_status = ${w.bind(a.status, "text")}`);
      if (a.category_id) w.add(`v.category_id = ${w.bind(a.category_id, "uuid")}`);
      return many(
        db,
        `${STORE_ROW} ${w} order by v.created_at desc ${page(w, a)}`,
        w.params,
      );
    },
  },
  {
    name: "get_store",
    title: "Store details",
    description:
      "One store in full: its settings, owner, category, how many products " +
      "it lists and how many orders it has taken.",
    permission: ["vendors.view"],
    readOnly: true,
    input: object({ vendor_id: uuid("The store's id.") }, ["vendor_id"]),
    run: async (db, a) => {
      const store = await db.json(
        `select to_jsonb(v) || jsonb_build_object(
           'owner', (select jsonb_build_object(
                       'id', p.id, 'full_name', p.full_name, 'phone', p.phone,
                       'is_blocked', p.is_blocked)
                     from public.profiles p where p.id = v.owner_id),
           'category_name', (select c.name from public.vendor_categories c
                             where c.id = v.category_id),
           'product_count', (select count(*) from public.products pr
                             where pr.vendor_id = v.id),
           'order_count', (select count(*) from public.orders o
                           where o.vendor_id = v.id),
           'orders_last_30_days', (
             select count(*) from public.orders o
             where o.vendor_id = v.id
               and o.created_at >= now() - interval '30 days'))
         from public.vendors v where v.id = $1::uuid`,
        [a.vendor_id],
      );
      if (!store) throw new ToolError("NOT_FOUND", "No such store.");
      return store;
    },
  },
  {
    name: "approve_store",
    title: "Approve a store",
    description:
      "Approves a store's application: it becomes active, visible to " +
      "customers and able to take orders. Confirm with the admin before " +
      "calling.",
    permission: ["vendors.approve"],
    readOnly: false,
    input: object({ vendor_id: uuid("The store's id.") }, ["vendor_id"]),
    run: (db, a) => decide(db, "vendor", a.vendor_id, true),
  },
  {
    name: "reject_store",
    title: "Turn down a store application",
    description:
      "Turns down a store that is still pending approval. Works only on " +
      "pending applicants; an already-approved store cannot be suspended " +
      "from here. Confirm with the admin before calling.",
    permission: ["vendors.approve"],
    readOnly: false,
    input: object({ vendor_id: uuid("The store's id.") }, ["vendor_id"]),
    run: (db, a) => decide(db, "vendor", a.vendor_id, false),
  },
  {
    name: "create_store",
    title: "Create a store and its owner's login",
    description:
      "Sets up a new store in one step: a login for the owner (email and " +
      "password) and the store itself, approved and open unless approve is " +
      "false. This puts a live store in front of customers and creates an " +
      "account somebody can sign in to, so read every detail back to the " +
      "admin and get a yes before calling. The password you choose appears " +
      "in this conversation: make it long and random, and tell the admin to " +
      "have the owner change it after first sign-in. The menu is not " +
      "created here; that is done at the dashboard.",
    permission: ["vendors.approve"],
    readOnly: false,
    input: object({
      owner_email: text("The owner's email; they sign in with it.", 200),
      owner_password: {
        type: "string",
        minLength: 8,
        maxLength: 72,
        description: "Password for the owner's login, at least 8 characters.",
      },
      owner_full_name: text("The owner's name.", 120),
      owner_phone: text("The owner's phone.", 30),
      owner_username: text(
        "Optional login name the owner can use instead of the email: 3-20 " +
          "letters, digits, dots or underscores.",
        20,
      ),
      name: text("The store's name.", 120),
      category_id: uuid("The store's category (see list_categories)."),
      address_text: text("The store's address, as customers should read it.", 300),
      lat: { type: "number", minimum: -90, maximum: 90, description: "Store latitude." },
      lng: { type: "number", minimum: -180, maximum: 180, description: "Store longitude." },
      description: text("A line or two about the store.", 500),
      phone: text("The store's phone. Defaults to the owner's.", 30),
      min_order_amount: amount("Smallest order the store takes. Default 0."),
      avg_prep_minutes: count("Usual preparation time in minutes. Default 20.", 1, 600),
      delivery_fee: amount("The store's delivery fee. Default 0."),
      delivery_radius_km: {
        type: "number",
        minimum: 0.5,
        maximum: 300,
        description: "How far the store delivers, in km. Default 10.",
      },
      billing_model: oneOf(
        ["commission", "subscription"],
        "How the platform charges the store. Default commission.",
      ),
      commission_rate: {
        type: "number",
        minimum: 0,
        maximum: 100,
        description: "Commission percent, for billing_model commission. Default 10.",
      },
      subscription_fee: amount("Subscription fee, for billing_model subscription."),
      logo_url: text("Public URL of the logo. Must already be hosted.", 1000),
      cover_url: text("Public URL of the cover image. Must already be hosted.", 1000),
      approve: flag(
        "true (default): the store is active and open at once. false: it " +
          "waits as pending until approved.",
      ),
    }, [
      "owner_email",
      "owner_password",
      "owner_full_name",
      "name",
      "category_id",
      "address_text",
      "lat",
      "lng",
    ]),
    run: async (db, a, _caller, accounts) => {
      if (!accounts) {
        throw new ToolError("UNAVAILABLE", "Logins cannot be created here.");
      }
      const email = a.owner_email.trim().toLowerCase();
      if (!EMAIL.test(email)) {
        throw new ToolError("INVALID_EMAIL", "owner_email is not an email address.");
      }
      const username = a.owner_username?.trim() || null;
      if (username && !USERNAME.test(username)) {
        throw new ToolError(
          "INVALID_USERNAME",
          "owner_username must be 3-20 letters, digits, dots or underscores.",
        );
      }
      // Checked before the login exists, so a typo in the category does not
      // cost a create-then-delete of somebody's account.
      const category = await db.json(
        "select id from public.vendor_categories where id = $1::uuid",
        [a.category_id],
      );
      if (!category) throw new ToolError("NOT_FOUND", "No such category.");

      const ownerPhone = a.owner_phone?.trim() || null;
      const approve = a.approve !== false;
      const billing = a.billing_model === "subscription" ? "subscription" : "commission";

      const ownerId = await accounts.createLogin({
        email,
        password: a.owner_password,
        fullName: a.owner_full_name.trim(),
        phone: ownerPhone,
        username,
        role: "vendor",
      });

      try {
        // Same values the dashboard's "create account" writes.
        const store = await insertRow(db, "vendors", STORE_COLUMNS, {
          owner_id: ownerId,
          name: a.name.trim(),
          description: a.description?.trim() || null,
          category_id: a.category_id,
          phone: a.phone?.trim() || ownerPhone,
          address_text: a.address_text.trim(),
          lat: a.lat,
          lng: a.lng,
          min_order_amount: a.min_order_amount ?? 0,
          avg_prep_minutes: a.avg_prep_minutes ?? 20,
          delivery_fee: a.delivery_fee ?? 0,
          delivery_radius_km: a.delivery_radius_km ?? 10,
          billing_model: billing,
          commission_rate: billing === "commission" ? (a.commission_rate ?? 10) : 0,
          subscription_fee: billing === "subscription" ? (a.subscription_fee ?? 0) : 0,
          logo_url: a.logo_url ?? null,
          cover_url: a.cover_url ?? null,
          approval_status: approve ? "active" : "pending",
          // A store an operator sets up is ready now; one held for review
          // stays shut until somebody approves it.
          is_open: approve,
        });
        await audit(db, "vendor.create_account", "vendor", store.id, {
          email,
          approved: approve,
        });
        return {
          created: true,
          vendor_id: store.id,
          owner_id: ownerId,
          owner_email: email,
          owner_username: username,
          approval_status: store.approval_status,
          is_open: store.is_open,
        };
      } catch (error) {
        // A login with no store behind it is one nobody can use or register
        // again, so it goes.
        await accounts.deleteLogin(ownerId).catch(() => {});
        throw error;
      }
    },
  },

  // -- Drivers --------------------------------------------------------------
  {
    name: "list_drivers",
    title: "List drivers",
    description:
      "Drivers with their approval status, whether they are online, and " +
      "rating. Filter by status or online, or search by name or phone.",
    permission: ["drivers.view"],
    readOnly: true,
    input: object({
      query: text("Part of the driver's name or phone.", 100),
      status: oneOf(APPROVAL, "Only drivers with this approval status."),
      online: flag("Only drivers who are online (true) or offline (false)."),
      limit,
      offset,
    }),
    run: (db, a) => {
      const w = new Where();
      if (a.query) {
        const q = w.bind(like(a.query), "text");
        w.add(`(p.full_name ilike ${q} or p.phone ilike ${q})`);
      }
      if (a.status) w.add(`d.approval_status = ${w.bind(a.status, "text")}`);
      if (a.online !== undefined) {
        w.add(`d.is_online = ${w.bind(a.online, "boolean")}`);
      }
      return many(
        db,
        `${DRIVER_ROW} ${w} order by p.created_at desc ${page(w, a)}`,
        w.params,
      );
    },
  },
  {
    name: "get_driver",
    title: "Driver details",
    description:
      "One driver: status, documents on file, rating, deliveries completed " +
      "and the order they are carrying now, if any.",
    permission: ["drivers.view"],
    readOnly: true,
    input: object({ driver_id: uuid("The driver's id.") }, ["driver_id"]),
    run: async (db, a) => {
      const driver = await db.json(
        `select to_jsonb(t) || jsonb_build_object(
           'delivered_orders', (select count(*) from public.orders o
                                where o.driver_id = t.id
                                  and o.status = 'delivered'),
           'current_order', (select jsonb_build_object(
                               'id', o.id, 'order_number', o.order_number,
                               'status', o.status)
                             from public.orders o
                             where o.driver_id = t.id
                               and o.status in ('ready_for_pickup',
                                                'out_for_delivery')
                             order by o.created_at desc limit 1))
         from (${DRIVER_ROW} where d.id = $1::uuid) t`,
        [a.driver_id],
      );
      if (!driver) throw new ToolError("NOT_FOUND", "No such driver.");
      return driver;
    },
  },
  {
    name: "approve_driver",
    title: "Approve a driver",
    description:
      "Approves a driver's application so they can go online and take " +
      "deliveries. Confirm with the admin before calling.",
    permission: ["drivers.approve"],
    readOnly: false,
    input: object({ driver_id: uuid("The driver's id.") }, ["driver_id"]),
    run: (db, a) => decide(db, "driver", a.driver_id, true),
  },
  {
    name: "reject_driver",
    title: "Turn down a driver application",
    description:
      "Turns down a driver who is still pending approval, with the reason " +
      "they will be shown. Works only on pending applicants. Confirm with " +
      "the admin before calling.",
    permission: ["drivers.approve"],
    readOnly: false,
    input: object({
      driver_id: uuid("The driver's id."),
      reason: text("Why, in words the driver will read.", 500),
    }, ["driver_id", "reason"]),
    run: (db, a) => decide(db, "driver", a.driver_id, false, a.reason),
  },
  {
    name: "pending_approvals",
    title: "Pending approvals",
    description:
      "Every store and driver waiting to be approved, oldest first.",
    permission: ["vendors.view", "drivers.view"],
    readOnly: true,
    input: object({}),
    run: (db) =>
      // Each half answers only if the admin may see that half; an admin who
      // handles drivers alone gets the drivers and no store list.
      db.json(
        `select jsonb_strip_nulls(jsonb_build_object(
           'stores', case when public.has_permission('vendors.view') then (
             select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]'::jsonb)
             from (${STORE_ROW} where v.approval_status = 'pending') t) end,
           'drivers', case when public.has_permission('drivers.view') then (
             select coalesce(jsonb_agg(to_jsonb(t) order by t.joined_at), '[]'::jsonb)
             from (${DRIVER_ROW} where d.approval_status = 'pending') t) end))`,
      ),
  },

  // -- Complaints -----------------------------------------------------------
  {
    name: "list_complaints",
    title: "List complaints",
    description:
      "Customer complaints, most recently active first. By default only " +
      "the ones not yet resolved.",
    permission: ["support.handle"],
    readOnly: true,
    input: object({
      status: oneOf(
        ["pending", "in_progress", "resolved", "all"],
        "Which complaints. Default: everything not resolved.",
      ),
      limit,
      offset,
    }),
    run: (db, a) => {
      const w = new Where();
      if (!a.status) w.add("r.status <> 'resolved'");
      else if (a.status !== "all") w.add(`r.status = ${w.bind(a.status, "text")}`);
      return many(
        db,
        `${COMPLAINT_ROW} ${w}
         order by coalesce(r.last_message_at, r.created_at) desc ${page(w, a)}`,
        w.params,
      );
    },
  },
  {
    name: "get_complaint",
    title: "Complaint details",
    description: "One complaint with the whole conversation so far.",
    permission: ["support.handle"],
    readOnly: true,
    input: object({ report_id: uuid("The complaint's id.") }, ["report_id"]),
    run: async (db, a) => {
      const complaint = await db.json(
        `select to_jsonb(t) || jsonb_build_object('messages', (
           select coalesce(jsonb_agg(jsonb_build_object(
                    'id', m.id, 'is_from_admin', m.is_from_admin,
                    'message', m.message, 'created_at', m.created_at)
                    order by m.created_at), '[]'::jsonb)
           from public.customer_report_messages m where m.report_id = t.id))
         from (${COMPLAINT_ROW} where r.id = $1::uuid) t`,
        [a.report_id],
      );
      if (!complaint) throw new ToolError("NOT_FOUND", "No such complaint.");
      return complaint;
    },
  },
  {
    name: "reply_to_complaint",
    title: "Reply to a complaint",
    description:
      "Sends the customer a reply on their complaint, and optionally marks " +
      "it resolved. The customer is notified and reads exactly this text, " +
      "so show the admin the wording before sending.",
    permission: ["support.handle"],
    readOnly: false,
    input: object({
      report_id: uuid("The complaint's id."),
      message: text("The reply, in the customer's language.", 2000),
      resolve: flag("Also mark the complaint resolved."),
    }, ["report_id"]),
    run: async (db, a) => {
      if (!a.message && !a.resolve) {
        throw new ToolError("INVALID_ARGUMENTS", "Give a message, or resolve.");
      }
      const messageId = await db.json(
        "select public.report_send_message($1::uuid, $2::text, $3::boolean)",
        [a.report_id, a.message ?? "", a.resolve === true],
      );
      await audit(db, "report.reply", "customer_report", a.report_id, {
        resolved: a.resolve === true,
      });
      return { sent: messageId !== null, message_id: messageId, resolved: a.resolve === true };
    },
  },

  // -- Support chat ---------------------------------------------------------
  {
    name: "list_support_threads",
    title: "List support chats",
    description:
      "Support conversations with customers, stores and drivers, most " +
      "recently active first, each with its latest message. By default only " +
      "open ones. A thread whose last message is not from an admin is " +
      "waiting for an answer.",
    permission: ["support.handle"],
    readOnly: true,
    input: object({
      status: oneOf(["open", "resolved", "all"], "Which chats. Default: open."),
      limit,
      offset,
    }),
    run: (db, a) => {
      const w = new Where();
      const status = a.status ?? "open";
      if (status !== "all") w.add(`t.status = ${w.bind(status, "text")}`);
      return many(
        db,
        `${THREAD_ROW} ${w} order by t.last_message_at desc ${page(w, a)}`,
        w.params,
      );
    },
  },
  {
    name: "get_support_thread",
    title: "Support chat messages",
    description: "One support conversation with its most recent messages.",
    permission: ["support.handle"],
    readOnly: true,
    input: object({
      thread_id: uuid("The chat's id."),
      limit,
    }, ["thread_id"]),
    run: async (db, a) => {
      const thread = await db.json(
        `select to_jsonb(t) || jsonb_build_object('messages', (
           select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at), '[]'::jsonb)
           from (select m.id, m.is_from_admin, m.is_automated, m.message,
                        m.attachment_name, m.attachment_type, m.created_at
                 from public.support_messages m
                 where m.thread_id = t.id
                 order by m.created_at desc limit $2::integer) m))
         from (${THREAD_ROW} where t.id = $1::uuid) t`,
        [a.thread_id, a.limit ?? 50],
      );
      if (!thread) throw new ToolError("NOT_FOUND", "No such support chat.");
      return thread;
    },
  },
  {
    name: "reply_to_support_thread",
    title: "Reply in a support chat",
    description:
      "Sends a message in a support chat as the admin. The person is " +
      "notified and reads exactly this text, so show the admin the wording " +
      "before sending.",
    permission: ["support.handle"],
    readOnly: false,
    input: object({
      thread_id: uuid("The chat's id."),
      message: text("The message, in the person's language.", 2000),
    }, ["thread_id", "message"]),
    run: async (db, a) => {
      const exists = await db.json(
        "select id from public.support_threads where id = $1::uuid",
        [a.thread_id],
      );
      if (!exists) throw new ToolError("NOT_FOUND", "No such support chat.");
      const messageId = await db.json(
        `insert into public.support_messages
           (thread_id, sender_id, is_from_admin, message)
         values ($1::uuid, auth.uid(), true, $2::text)
         returning id`,
        [a.thread_id, a.message.trim()],
      );
      await audit(db, "support.reply", "support_thread", a.thread_id);
      return { sent: true, message_id: messageId };
    },
  },
  {
    name: "set_support_thread_status",
    title: "Resolve or reopen a support chat",
    description: "Marks a support chat resolved, or opens it again.",
    permission: ["support.handle"],
    readOnly: false,
    input: object({
      thread_id: uuid("The chat's id."),
      status: oneOf(["open", "resolved"], "The new status."),
    }, ["thread_id", "status"]),
    run: async (db, a) => {
      const thread = await updateRow(
        db,
        "support_threads",
        { status: "text" },
        a.thread_id,
        a,
      );
      await audit(db, "support.status", "support_thread", a.thread_id, {
        status: a.status,
      });
      return { id: thread.id, status: thread.status };
    },
  },

  // -- Reports and balances -------------------------------------------------
  {
    name: "platform_report",
    title: "Platform report",
    description:
      "The platform's totals for a period: orders, sales, commission, " +
      "delivery, discounts and what the platform kept.",
    permission: ["reports.view"],
    readOnly: true,
    input: object(range),
    run: (db, a) =>
      db.json(
        "select public.admin_platform_report($1::timestamptz, $2::timestamptz)",
        [a.from ?? null, a.to ?? null],
      ),
  },
  {
    name: "finance_overview",
    title: "Money overview",
    description:
      "Where the money is for a period: collected, owed to stores and " +
      "drivers, cash still with drivers, and the platform's share.",
    permission: ["reports.view"],
    readOnly: true,
    input: object(range),
    run: (db, a) =>
      db.json(
        "select public.admin_finance_overview($1::timestamptz, $2::timestamptz)",
        [a.from ?? null, a.to ?? null],
      ),
  },
  {
    name: "store_sales_report",
    title: "Sales by store",
    description:
      "Per store for a period: orders, gross sales, discounts the store " +
      "funded, commission and net payout.",
    permission: ["reports.view"],
    readOnly: true,
    input: object(range),
    run: (db, a) =>
      many(
        db,
        "select * from public.admin_vendor_sales_report($1::timestamptz, $2::timestamptz)",
        [a.from ?? null, a.to ?? null],
      ),
  },
  {
    name: "driver_payout_report",
    title: "Earnings by driver",
    description:
      "Per driver for a period: deliveries, delivery fees, the driver's " +
      "share, tips and net payout.",
    permission: ["reports.view"],
    readOnly: true,
    input: object(range),
    run: (db, a) =>
      many(
        db,
        "select * from public.admin_driver_payout_report($1::timestamptz, $2::timestamptz)",
        [a.from ?? null, a.to ?? null],
      ),
  },
  {
    name: "store_balances",
    title: "Store balances",
    description:
      "What each store is owed right now, what it owes in cash, and when it " +
      "was last paid. Read-only: paying a store is done at the dashboard.",
    permission: ["reports.view"],
    readOnly: true,
    input: object({}),
    run: (db) => many(db, "select * from public.admin_vendor_balances()"),
  },
  {
    name: "driver_balances",
    title: "Driver balances",
    description:
      "What each driver is owed right now, the cash they are holding for " +
      "the platform, and when they were last settled. Read-only: settling " +
      "is done at the dashboard.",
    permission: ["reports.view"],
    readOnly: true,
    input: object({}),
    run: (db) => many(db, "select * from public.admin_driver_balances()"),
  },

  // -- Coupons --------------------------------------------------------------
  {
    name: "list_coupons",
    title: "List coupons",
    description:
      "Promo codes with their rules and how many times each has been used.",
    permission: ["promos.manage"],
    readOnly: true,
    input: object({
      active: flag("Only active (true) or inactive (false) codes."),
      vendor_id: uuid("Only codes limited to this store."),
      limit,
      offset,
    }),
    run: (db, a) => {
      const w = new Where();
      if (a.active !== undefined) {
        w.add(`c.is_active = ${w.bind(a.active, "boolean")}`);
      }
      if (a.vendor_id) w.add(`c.vendor_id = ${w.bind(a.vendor_id, "uuid")}`);
      return many(
        db,
        `select c.*, v.name as vendor_name
         from public.coupons c
         left join public.vendors v on v.id = c.vendor_id
         ${w} order by c.created_at desc ${page(w, a)}`,
        w.params,
      );
    },
  },
  {
    name: "create_coupon",
    title: "Create a coupon",
    description:
      "Creates a promo code. A platform-funded discount is money the " +
      "platform gives away on every use, so state the terms back to the " +
      "admin and get a yes before calling. Each customer may use a code " +
      "once unless per_user_limit says otherwise.",
    permission: ["promos.manage"],
    readOnly: false,
    input: object(couponFields, ["code", "discount_type"]),
    run: async (db, a) => {
      const isFreeDelivery = a.discount_type === "free_delivery";
      if (!isFreeDelivery && !(a.value > 0)) {
        throw new ToolError("INVALID_ARGUMENTS", "value must be above 0.");
      }
      if (a.discount_type === "percentage" && a.value > 100) {
        throw new ToolError("INVALID_ARGUMENTS", "A percentage cannot exceed 100.");
      }
      // Same defaults as the dashboard's form.
      const coupon = await insertRow(db, "coupons", COUPON_COLUMNS, {
        per_user_limit: 1,
        is_active: true,
        ...a,
        code: a.code.trim().toUpperCase(),
        value: isFreeDelivery ? 0 : a.value,
        // Only a store-scoped code can be charged to the store.
        funded_by: a.vendor_id ? (a.funded_by ?? "platform") : "platform",
      });
      await audit(db, "coupon.create", "coupon", coupon.id, { code: coupon.code });
      return coupon;
    },
  },
  {
    name: "update_coupon",
    title: "Change a coupon",
    description:
      "Changes a promo code's rules, or switches it on or off with " +
      "is_active. Only the fields given are changed; send null to clear " +
      "an optional one. Confirm the change with the admin first.",
    permission: ["promos.manage"],
    readOnly: false,
    input: object(
      { coupon_id: uuid("The coupon's id."), ...couponFields },
      ["coupon_id"],
    ),
    run: async (db, a) => {
      const changes = { ...a };
      if (typeof changes.code === "string") {
        changes.code = changes.code.trim().toUpperCase();
      }
      const coupon = await updateRow(
        db,
        "coupons",
        COUPON_COLUMNS,
        a.coupon_id,
        changes,
      );
      await audit(db, "coupon.update", "coupon", coupon.id, {
        code: coupon.code,
        changed: given(COUPON_COLUMNS, a),
      });
      return coupon;
    },
  },

  // -- Ads ------------------------------------------------------------------
  {
    name: "list_ads",
    title: "List ads",
    description:
      "Ads and banners shown in the customer app, with where each appears, " +
      "its schedule, and impressions and clicks.",
    permission: ["ads.manage"],
    readOnly: true,
    input: object({
      active: flag("Only active (true) or inactive (false) ads."),
      placement: adFields.placement,
      limit,
      offset,
    }),
    run: (db, a) => {
      const w = new Where();
      if (a.active !== undefined) {
        w.add(`b.is_active = ${w.bind(a.active, "boolean")}`);
      }
      if (a.placement) w.add(`b.placement = ${w.bind(a.placement, "text")}`);
      return many(
        db,
        `select b.*, v.name as vendor_name
         from public.banners b
         left join public.vendors v on v.id = b.vendor_id
         ${w} order by b.placement, b.sort_order, b.created_at desc ${page(w, a)}`,
        w.params,
      );
    },
  },
  {
    name: "create_ad",
    title: "Create an ad",
    description:
      "Puts an ad in the customer app. The image must already be hosted at " +
      "a public URL; this cannot upload files. It goes live as soon as it " +
      "is active and inside its schedule, so confirm with the admin first, " +
      "or create it with is_active false.",
    permission: ["ads.manage"],
    readOnly: false,
    input: object(adFields, ["image_url"]),
    run: async (db, a) => {
      const ad = await insertRow(db, "banners", AD_COLUMNS, a);
      await audit(db, "ad.create", "banner", ad.id, {
        placement: ad.placement,
        title: ad.title,
      });
      return ad;
    },
  },
  {
    name: "update_ad",
    title: "Change an ad",
    description:
      "Changes an ad, or switches it on or off with is_active. Only the " +
      "fields given are changed; send null to clear an optional one.",
    permission: ["ads.manage"],
    readOnly: false,
    input: object({ ad_id: uuid("The ad's id."), ...adFields }, ["ad_id"]),
    run: async (db, a) => {
      const ad = await updateRow(db, "banners", AD_COLUMNS, a.ad_id, a);
      await audit(db, "ad.update", "banner", ad.id, {
        changed: given(AD_COLUMNS, a),
      });
      return ad;
    },
  },

  // -- Campaigns ------------------------------------------------------------
  {
    name: "list_notification_campaigns",
    title: "List announcements",
    description:
      "Push announcements sent or drafted, with who they went to and how " +
      "many were delivered. Read-only: sending one is done at the dashboard.",
    permission: ["notifications.send"],
    readOnly: true,
    input: object({
      status: oneOf(["draft", "sending", "sent", "failed"], "Only this status."),
      limit,
      offset,
    }),
    run: (db, a) => {
      const w = new Where();
      if (a.status) w.add(`n.status = ${w.bind(a.status, "text")}`);
      return many(
        db,
        `select n.* from public.notification_campaigns n
         ${w} order by n.created_at desc ${page(w, a)}`,
        w.params,
      );
    },
  },
  {
    name: "list_price_campaigns",
    title: "List price campaigns",
    description:
      "Temporary price mark-ups, with their scope, schedule and status. " +
      "Read-only: starting or ending one changes prices and is done at the " +
      "dashboard.",
    permission: ["catalog.manage"],
    readOnly: true,
    input: object({ limit, offset }),
    run: (db, a) => {
      const w = new Where();
      return many(
        db,
        `select c.*, v.name as vendor_name
         from public.price_campaigns c
         left join public.vendors v on v.id = c.vendor_id
         order by c.created_at desc ${page(w, a)}`,
        w.params,
      );
    },
  },

  // -- Categories -----------------------------------------------------------
  {
    name: "list_categories",
    title: "List store categories",
    description:
      "The categories stores are grouped under, in display order, with how " +
      "many stores each has. A category with a parent_id is a sub-category.",
    permission: ["catalog.manage", "vendors.view"],
    readOnly: true,
    input: object({}),
    run: (db) =>
      many(
        db,
        `select c.*, (select count(*) from public.vendors v
                      where v.category_id = c.id) as store_count
         from public.vendor_categories c
         order by c.parent_id nulls first, c.sort_order, c.name`,
      ),
  },
  {
    name: "create_category",
    title: "Create a store category",
    description: "Adds a category (or, with parent_id, a sub-category).",
    permission: ["catalog.manage"],
    readOnly: false,
    input: object(categoryFields, ["name"]),
    run: async (db, a) => {
      const category = await insertRow(db, "vendor_categories", CATEGORY_COLUMNS, a);
      await audit(db, "category.create", "vendor_category", category.id, {
        name: category.name,
      });
      return category;
    },
  },
  {
    name: "update_category",
    title: "Change a store category",
    description:
      "Renames, reorders, hides or shows a category. Only the fields given " +
      "are changed. Hiding one hides it from customers at once.",
    permission: ["catalog.manage"],
    readOnly: false,
    input: object(
      { category_id: uuid("The category's id."), ...categoryFields },
      ["category_id"],
    ),
    run: async (db, a) => {
      const category = await updateRow(
        db,
        "vendor_categories",
        CATEGORY_COLUMNS,
        a.category_id,
        a,
      );
      await audit(db, "category.update", "vendor_category", category.id, {
        changed: given(CATEGORY_COLUMNS, a),
      });
      return category;
    },
  },

  // -- Service areas --------------------------------------------------------
  {
    name: "list_service_areas",
    title: "List service areas",
    description:
      "The circles on the map the platform delivers inside: centre, radius " +
      "and whether each is active.",
    permission: ["content.manage"],
    readOnly: true,
    input: object({}),
    run: (db) =>
      many(db, "select a.* from public.service_areas a order by a.name"),
  },
  {
    name: "create_service_area",
    title: "Create a service area",
    description:
      "Adds an area the platform delivers in. Customers inside it can " +
      "order as soon as it is active, so confirm the centre and radius " +
      "with the admin first.",
    permission: ["content.manage"],
    readOnly: false,
    input: object(areaFields, ["name", "lat", "lng", "radius_km"]),
    run: async (db, a) => {
      const area = await insertRow(db, "service_areas", AREA_COLUMNS, a);
      await audit(db, "service_area.create", "service_area", area.id, {
        name: area.name,
        radius_km: area.radius_km,
      });
      return area;
    },
  },
  {
    name: "update_service_area",
    title: "Change a service area",
    description:
      "Moves, resizes, renames, or switches a service area on or off. " +
      "Switching one off stops new orders from customers inside it, so " +
      "confirm with the admin first.",
    permission: ["content.manage"],
    readOnly: false,
    input: object(
      { area_id: uuid("The service area's id."), ...areaFields },
      ["area_id"],
    ),
    run: async (db, a) => {
      const area = await updateRow(db, "service_areas", AREA_COLUMNS, a.area_id, a);
      await audit(db, "service_area.update", "service_area", area.id, {
        changed: given(AREA_COLUMNS, a),
      });
      return area;
    },
  },

  // -- People and the log ---------------------------------------------------
  {
    name: "search_users",
    title: "Search users",
    description:
      "Finds accounts by name, email or phone, to get the id other tools " +
      "need. Read-only: blocking or deleting an account is done at the " +
      "dashboard.",
    permission: ["users.block"],
    readOnly: true,
    input: object({ query: text("Name, email or phone.", 100) }, ["query"]),
    run: (db, a) =>
      many(db, "select * from public.admin_search_users($1::text)", [
        a.query.trim(),
      ]),
  },
  {
    name: "list_admin_log",
    title: "Admin action log",
    description:
      "The record of what admins did, newest first. via_claude shows only " +
      "what was done through this connection rather than at the dashboard.",
    permission: ["staff.manage"],
    readOnly: true,
    input: object({
      via_claude: flag("Only actions taken through Claude."),
      limit,
      offset,
    }),
    run: (db, a) => {
      const w = new Where();
      if (a.via_claude) w.add("l.detail ->> 'via' = 'claude'");
      return many(
        db,
        `select l.id, l.action, l.target_type, l.target_id, l.detail,
                l.created_at, l.actor_id, p.full_name as actor_name
         from public.admin_audit_log l
         left join public.profiles p on p.id = l.actor_id
         ${w} order by l.created_at desc ${page(w, a)}`,
        w.params,
      );
    },
  },
];

const byName = new Map(tools.map((tool) => [tool.name, tool]));

export const findTool = (name: string) => byName.get(name);

/// The tool list as the protocol wants it.
export function describeTools() {
  return tools.map((tool) => ({
    name: tool.name,
    title: tool.title,
    description: tool.description,
    inputSchema: toJsonSchema(tool.input),
    annotations: {
      title: tool.title,
      readOnlyHint: tool.readOnly,
      destructiveHint: false,
      openWorldHint: false,
    },
  }));
}

/// Checks the call, checks the admin may make it, then runs it.
///
/// The permission is asked of the database as the admin, in the transaction
/// the tool is about to run in — the same `has_permission` the RPCs and row
/// policies use, so this gate and theirs cannot disagree.
export async function runTool(
  db: Db,
  caller: Caller,
  name: string,
  args: unknown,
  accounts?: Accounts,
): Promise<unknown> {
  const tool = findTool(name);
  if (!tool) throw new ToolError("UNKNOWN_TOOL", `No tool named ${name}.`);

  const input = args ?? {};
  const problems = validate(tool.input, input);
  if (problems.length > 0) {
    throw new ToolError("INVALID_ARGUMENTS", problems.join("; "));
  }

  const allowed = tool.permission
    ? await db.json<boolean>(
      "select bool_or(public.has_permission(k)) from unnest($1::text::text[]) k",
      [`{${tool.permission.join(",")}}`],
    )
    : await db.json<boolean>("select public.is_admin()");
  if (allowed !== true) {
    throw new ToolError(
      "FORBIDDEN",
      tool.permission
        ? `This admin's role does not include ${tool.permission.join(" or ")}.`
        : "This account is not an admin.",
    );
  }

  return await tool.run(db, input as Record<string, any>, caller, accounts);
}
