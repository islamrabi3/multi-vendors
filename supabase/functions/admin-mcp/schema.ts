// The small slice of JSON Schema the tools describe their arguments in, and
// the check that an incoming call actually matches it.
//
// One definition does both jobs: it is sent to the client as the tool's
// `inputSchema`, and it is what the arguments are validated against before a
// single query runs. Two descriptions of the same thing would drift.

export type Prop =
  & { description?: string; nullable?: boolean }
  & (
    | {
      type: "string";
      enum?: readonly string[];
      format?: "uuid" | "date-time";
      minLength?: number;
      maxLength?: number;
    }
    | { type: "number" | "integer"; minimum?: number; maximum?: number }
    | { type: "boolean" }
  );

export interface ObjectSchema {
  type: "object";
  properties: Record<string, Prop>;
  required?: readonly string[];
  additionalProperties: false;
}

export function object(
  properties: Record<string, Prop>,
  required: readonly string[] = [],
): ObjectSchema {
  return { type: "object", properties, required, additionalProperties: false };
}

export const uuid = (description: string): Prop => ({
  type: "string",
  format: "uuid",
  description,
});

export const text = (description: string, maxLength = 500): Prop => ({
  type: "string",
  minLength: 1,
  maxLength,
  description,
});

export const oneOf = (values: readonly string[], description: string): Prop => ({
  type: "string",
  enum: values,
  description,
});

export const when = (description: string): Prop => ({
  type: "string",
  format: "date-time",
  description: `${description} ISO 8601, e.g. 2026-10-03T00:00:00Z.`,
});

export const flag = (description: string): Prop => ({
  type: "boolean",
  description,
});

export const amount = (description: string, minimum = 0): Prop => ({
  type: "number",
  minimum,
  description,
});

export const count = (
  description: string,
  minimum = 0,
  maximum = 1_000_000,
): Prop => ({ type: "integer", minimum, maximum, description });

/// A field that may be sent as null to clear it.
export const clearable = (prop: Prop): Prop => ({ ...prop, nullable: true });

export const limit: Prop = {
  type: "integer",
  minimum: 1,
  maximum: 100,
  description: "How many rows to return (default 25, at most 100).",
};

export const offset: Prop = {
  type: "integer",
  minimum: 0,
  maximum: 100_000,
  description: "Rows to skip, for paging (default 0).",
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// The JSON Schema sent to the client. `nullable` is ours, not the standard's,
/// so it is spelled the standard way on the way out.
export function toJsonSchema(schema: ObjectSchema): Record<string, unknown> {
  const properties: Record<string, unknown> = {};
  for (const [name, prop] of Object.entries(schema.properties)) {
    const { nullable, ...rest } = prop;
    properties[name] = nullable ? { ...rest, type: [rest.type, "null"] } : rest;
  }
  return {
    type: "object",
    properties,
    required: [...(schema.required ?? [])],
    additionalProperties: false,
  };
}

/// Every reason [args] does not fit [schema]; empty when it does.
export function validate(schema: ObjectSchema, args: unknown): string[] {
  if (args === null || typeof args !== "object" || Array.isArray(args)) {
    return ["arguments must be an object"];
  }
  const input = args as Record<string, unknown>;
  const problems: string[] = [];

  for (const name of schema.required ?? []) {
    if (input[name] === undefined || input[name] === null) {
      problems.push(`${name} is required`);
    }
  }

  for (const [name, value] of Object.entries(input)) {
    const prop = schema.properties[name];
    if (!prop) {
      problems.push(`${name} is not a known argument`);
      continue;
    }
    if (value === undefined) continue;
    if (value === null) {
      if (!prop.nullable && !(schema.required ?? []).includes(name)) {
        problems.push(`${name} cannot be null`);
      }
      continue;
    }

    if (prop.type === "string") {
      if (typeof value !== "string") {
        problems.push(`${name} must be a string`);
        continue;
      }
      if (prop.enum && !prop.enum.includes(value)) {
        problems.push(`${name} must be one of: ${prop.enum.join(", ")}`);
      }
      if (prop.format === "uuid" && !UUID.test(value)) {
        problems.push(`${name} must be a UUID`);
      }
      if (prop.format === "date-time" && Number.isNaN(Date.parse(value))) {
        problems.push(`${name} must be an ISO 8601 date-time`);
      }
      if (prop.minLength !== undefined && value.trim().length < prop.minLength) {
        problems.push(`${name} cannot be empty`);
      }
      if (prop.maxLength !== undefined && value.length > prop.maxLength) {
        problems.push(`${name} is longer than ${prop.maxLength} characters`);
      }
    } else if (prop.type === "boolean") {
      if (typeof value !== "boolean") problems.push(`${name} must be a boolean`);
    } else {
      if (typeof value !== "number" || !Number.isFinite(value)) {
        problems.push(`${name} must be a number`);
        continue;
      }
      if (prop.type === "integer" && !Number.isInteger(value)) {
        problems.push(`${name} must be a whole number`);
      }
      if (prop.minimum !== undefined && value < prop.minimum) {
        problems.push(`${name} must be at least ${prop.minimum}`);
      }
      if (prop.maximum !== undefined && value > prop.maximum) {
        problems.push(`${name} must be at most ${prop.maximum}`);
      }
    }
  }
  return problems;
}
