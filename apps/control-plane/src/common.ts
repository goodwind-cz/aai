import fs from "node:fs";
import path from "node:path";

export type CliArgs = Record<string, string | boolean | string[]> & { _: string[] };

export function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = { _: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) {
      args._.push(token);
      continue;
    }

    const key = token.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      args[key] = true;
      continue;
    }

    args[key] = next;
    index += 1;
  }
  return args;
}

export function ensureDir(targetPath: string): void {
  fs.mkdirSync(targetPath, { recursive: true });
}

export function readJson<T>(filePath: string): T {
  return JSON.parse(fs.readFileSync(filePath, "utf8")) as T;
}

export function writeJson(filePath: string, value: unknown): void {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

export function splitCsv(value: string | boolean | string[] | undefined): string[] {
  if (!value || Array.isArray(value)) {
    return Array.isArray(value) ? value : [];
  }

  return String(value)
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

export function shellQuote(value: string): string {
  if (/^[A-Za-z0-9_./:-]+$/.test(value)) {
    return value;
  }
  return JSON.stringify(value);
}

export function nowUtc(): string {
  return new Date().toISOString();
}

export function runtimeLog(event: string, payload: Record<string, unknown> = {}): void {
  const record = {
    ts: nowUtc(),
    event,
    ...payload
  };
  const line = `${JSON.stringify(record)}\n`;

  process.stderr.write(line);

  const logPath = process.env.AAI_CONTROL_PLANE_LOG;
  if (logPath) {
    ensureDir(path.dirname(logPath));
    fs.appendFileSync(logPath, line, "utf8");
  }
}

export function requireArg(args: CliArgs, key: string): string {
  const value = args[key];
  if (value === undefined || value === null || value === "" || typeof value !== "string") {
    throw new Error(`Missing required argument --${key}`);
  }
  return value;
}

export function printJson(value: unknown): void {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

export function resolveMaybe(filePath: string | boolean | string[] | undefined): string | null {
  return typeof filePath === "string" && filePath ? path.resolve(filePath) : null;
}
