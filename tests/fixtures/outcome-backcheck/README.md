# Outcome-backcheck semantic fixtures

Each `scenarios/scenario-NN` directory is a complete isolated validator input.
Give a fresh validator only that directory, the Validation instructions under
test, the output report path, and the following execution facts:

- repository root: this repository root
- scope ref: the directory basename
- intake source: `<scenario>/request.md`
- frozen spec source: `<scenario>/spec.md`
- implementation/evidence: the remaining files in the same scenario directory

Do not give scenario agents `oracle.json`, the feature brief, or the feature
specification. Write baseline reports under `semantic/baseline/` and candidate
reports under `semantic/candidate/`, named `<scenario>.md`. Preserve raw reports.
The scorer reads the separate oracle only after all fresh runs finish.
