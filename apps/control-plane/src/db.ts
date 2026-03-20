import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { ensureDir } from "./common.ts";

const schemaPath = new URL("../sql/001_init.sql", import.meta.url);

export type DatabaseHandle = {
  database: DatabaseSync;
  absolutePath: string;
};

export function openDatabase(dbPath: string): DatabaseHandle {
  const absolutePath = path.resolve(dbPath);
  ensureDir(path.dirname(absolutePath));
  const database = new DatabaseSync(absolutePath);
  database.exec("PRAGMA journal_mode = WAL;");
  database.exec("PRAGMA foreign_keys = ON;");
  database.exec(fs.readFileSync(schemaPath, "utf8"));
  return { database, absolutePath };
}

export function closeDatabase(handle: DatabaseHandle): void {
  handle.database.close();
}

export function parseJsonColumn(value: string | null): string[] {
  return value ? (JSON.parse(value) as string[]) : [];
}
