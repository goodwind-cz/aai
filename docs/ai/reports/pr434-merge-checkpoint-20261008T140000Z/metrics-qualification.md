# Metrics qualification

The canonical flush exported both child scopes and ran parent cleanup-only resume because an older parent row was already in METRICS. It did not append the newly queued parent runs to a fresh ledger row. Their actual harness usage and verdicts are preserved verbatim in runtime-before-flush.yaml and individual role-result receipts. No complete new parent aggregate or cost is claimed. No manual ledger arithmetic or duplicate flush row was invented.
