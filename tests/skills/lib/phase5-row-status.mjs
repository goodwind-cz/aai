// Shared reader for the RFC-0017 phase 5 row status (node-first-phase5-closeout, V5).
// The closed-spec suites that used to pin the row to `in progress` call this instead: `done` is accepted only
// when the latest "Re-measure after ..." section of docs/analysis/node-first-remaining-plan.md holds
// (hosted line passed, no logic file in its file table, twin duplication 0 code lines); `in progress` is
// accepted only while it does not hold. The full criteria are measured by TEST-4022 and TEST-4033.
// CLI: node phase5-row-status.mjs <rfc.md> [plan.md]   (plan defaults to docs/analysis/node-first-remaining-plan.md beside the RFC's docs dir, else this checkout's)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export function latestSectionHolds(planText) {
  const plan = planText.split("\n");
  let at = -1;
  plan.forEach((l, i) => { if (/^## \d+\. Re-measure after .+ \(\d{4}-\d{2}-\d{2}\)$/.test(l)) at = i; });
  if (at < 0) return false;
  let end = plan.length;
  for (let i = at + 1; i < plan.length; i += 1) if (plan[i].startsWith("## ")) { end = i; break; }
  const sec = plan.slice(at + 1, end);
  const h = sec.findIndex((l) => l.startsWith("| File |"));
  if (h < 0) return false;
  let logic = 0;
  for (let i = h + 2; i < sec.length && sec[i].startsWith("|"); i += 1) if (sec[i].split("|").map((c) => c.trim())[3] === "logic") logic += 1;
  const dup = sec.find((l) => l.startsWith("- Twin duplication: "));
  const hosted = sec.find((l) => l.startsWith("- Parity harness and Pester (H1 to H3): "));
  return logic === 0 && !!dup && dup.startsWith("- Twin duplication: 0 code lines") && !!hosted && /: passed\b/.test(hosted);
}

// returns "" when the row status is acceptable, else the problem
export function phase5RowProblem(rfcText, planText) {
  const rows = rfcText.split("\n").filter((l) => l.startsWith("| 5 |"));
  if (rows.length !== 1) return "the RFC phase 5 row appears " + rows.length + " times";
  const status = rows[0].split("|").map((c) => c.trim())[3];
  const holds = latestSectionHolds(planText);
  if (status === "done" && holds) return "";
  if (status === "in progress" && !holds) return "";
  return "the RFC phase 5 row status is '" + status + "' while the latest re-measure section " + (holds ? "holds (want done)" : "does not hold (want in progress)");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const rfc = process.argv[2];
  if (!rfc) { console.error("usage: phase5-row-status.mjs <rfc.md> [plan.md]"); process.exit(2); }
  // a seeded scratch RFC copy has no plan beside it: fall back to this checkout's plan
  const beside = path.join(path.dirname(rfc), "..", "analysis", "node-first-remaining-plan.md");
  const here = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "docs", "analysis", "node-first-remaining-plan.md");
  const plan = process.argv[3] || (fs.existsSync(beside) ? beside : here);
  const p = phase5RowProblem(fs.readFileSync(rfc, "utf8"), fs.readFileSync(plan, "utf8"));
  if (p) { console.log(p); process.exit(1); }
}
