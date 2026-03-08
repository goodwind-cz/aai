#!/bin/bash
# Create GitHub PR for comprehensive-improvements

# First, push the branch (you'll need to authenticate)
echo "Pushing branch to GitHub..."
git push origin feature/comprehensive-improvements

# Create PR using GitHub CLI
echo "Creating pull request..."
gh pr create \
  --title "feat: Comprehensive AAI improvements - testing, docs, integrations, and tooling" \
  --body "$(cat PR_DESCRIPTION.md)" \
  --base main \
  --head feature/comprehensive-improvements

echo "PR created! View at: $(gh pr view --json url -q .url)"
