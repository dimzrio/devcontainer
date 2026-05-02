---
name: create-pr
description: Create or update Pull Requests with well-structured titles and descriptions based on commit history and code changes. Use when the user asks to "create a PR", "open a pull request", "submit a PR", "update the PR description", or wants to push and create a GitHub pull request.
argument-hint: base-branch
compatibility: Requires git, gh
---

# Create Pull Request

## Context

You are creating a Pull Request on GitHub using the `gh` CLI.
Your goal is to produce a **clear, reviewable PR** that helps reviewers understand
what changed, why it changed, and how to verify it.

## Arguments

The user invoked this with: $ARGUMENTS

If a base branch was provided as an argument, use it as the target branch instead of the repo default.

## Prerequisites

Before doing anything, run these checks **in order** and stop if any fail:

```sh
# 1. Ensure we're not on a protected branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo "ERROR: Cannot create PR from protected branch '$CURRENT_BRANCH'. Create a feature branch first."
  exit 1
fi

# 2. Ensure gh CLI is authenticated
gh auth status || { echo "ERROR: gh CLI not authenticated. Run 'gh auth login' first."; exit 1; }

# 3. Determine the default branch of the repo
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')

# 4. Check if a PR already exists for this branch
EXISTING_PR=$(gh pr view "$CURRENT_BRANCH" --json number --jq '.number' 2>/dev/null)
```

## Step 1: Stage and Commit (if needed)

Only commit if there are uncommitted changes. Do NOT create empty commits.

```sh
# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "<generated_message>"
fi
```

### Pre-Commit Hook Failure Handling

If `git commit` fails due to pre-commit hooks (linters, formatters, type checkers, etc.),
you MUST attempt to fix the issues automatically. Follow this loop:

```
MAX_RETRIES=3
attempt=1

while attempt <= MAX_RETRIES:
  1. Run: git commit -m "<generated_message>"
  2. If commit succeeds → break, continue to Step 2
  3. If commit fails:
     a. Read the FULL error output carefully
     b. Identify the type of failure:

        FORMATTER errors (e.g., prettier, black, gofmt, rustfmt):
        → The formatter likely already fixed the files automatically
        → Run: git add -A
        → Retry the commit

        LINTER errors (e.g., eslint, golangci-lint, flake8, rubocop):
        → Read each error with file path and line number
        → Fix the code issues in the reported files
        → Run: git add -A
        → Retry the commit

        TYPE CHECK errors (e.g., tsc, mypy, pyright):
        → Read the type errors carefully
        → Fix type annotations, missing imports, or type mismatches
        → Run: git add -A
        → Retry the commit

        SECRET DETECTION errors (e.g., gitleaks, detect-secrets, trufflehog):
        → STOP IMMEDIATELY. Do NOT retry.
        → Alert the user: "Pre-commit detected a potential secret/credential in your changes."
        → List the flagged files and let the user decide how to proceed

        UNKNOWN / UNRECOVERABLE errors:
        → If you cannot understand or fix the error, STOP
        → Show the full error output to the user
        → Ask: "The pre-commit hook failed and I couldn't auto-fix it. How would you like to proceed?"

     c. Increment attempt

  4. If attempt > MAX_RETRIES:
     → STOP. Do not use --no-verify to bypass hooks.
     → Show all errors from the last attempt to the user
     → Ask: "I tried 3 times but couldn't resolve the pre-commit errors. Want me to show you the details?"
```

### Critical Rules for Pre-Commit Handling

- **NEVER use `git commit --no-verify` or `-n` to skip hooks** unless the user explicitly asks
- **NEVER ignore or suppress pre-commit output** — always read and act on it
- After each fix attempt, **re-stage all changes** with `git add -A` before retrying
- If a formatter auto-fixed files (common with prettier, black, isort), the fix is just re-staging
- Keep the **same commit message** across retries — don't change it just because the hook failed
- If the pre-commit error is about the **commit message format** itself (e.g., commitlint),
  fix the message to match the required format and retry

### Commit Message Rules

- Follow **Conventional Commits**: `type(scope): description`
- Valid types: `feat`, `fix`, `chore`, `docs`, `style`, `refactor`, `perf`, `test`, `ci`, `build`
- Scope is optional but encouraged (e.g., `feat(auth): add OAuth2 support`)
- Subject line: max **72 characters**, imperative mood, no period at end
- If the change is complex, add a body separated by a blank line
- Reference issue numbers when applicable: `fix(api): handle timeout errors (closes #42)`

## Step 2: Push the Branch

```sh
git push --set-upstream origin "$CURRENT_BRANCH"
```

## Step 3: Analyze Changes

Gather the full context of what this PR introduces. Use this data to generate
the title and description.

```sh
# Get all commits that are ahead of the default branch
COMMITS=$(git log "$DEFAULT_BRANCH".."$CURRENT_BRANCH" --pretty=format:"- %s (%h)" --reverse)

# Get a summary-level diff stat
DIFF_STAT=$(git diff "$DEFAULT_BRANCH"..."$CURRENT_BRANCH" --stat)

# Get the full diff for deeper analysis (use for understanding, not for pasting)
FULL_DIFF=$(git diff "$DEFAULT_BRANCH"..."$CURRENT_BRANCH")

# Count changes
FILES_CHANGED=$(git diff "$DEFAULT_BRANCH"..."$CURRENT_BRANCH" --name-only | wc -l)
INSERTIONS=$(git diff "$DEFAULT_BRANCH"..."$CURRENT_BRANCH" --shortstat | grep -oP '\d+ insertion' | grep -oP '\d+')
DELETIONS=$(git diff "$DEFAULT_BRANCH"..."$CURRENT_BRANCH" --shortstat | grep -oP '\d+ deletion' | grep -oP '\d+')
```

## Step 4: Generate PR Title

Rules for the title:
- Follow Conventional Commits format: `type(scope): description`
- Max **72 characters**
- Use imperative mood ("add", "fix", "update" — not "added", "fixes", "updated")
- Be specific — avoid vague titles like "update code" or "fix bug"
- If there's a single commit, the commit message IS the title (if it's good enough)
- If there are multiple commits, summarize the overall change

Examples of GOOD titles:
- `feat(gateway): migrate ingress rules to Gateway API`
- `fix(keda): resolve duplicate HTTPRoute in staging`
- `chore(ci): add automated image tag update via Flux`

Examples of BAD titles:
- `update files` (too vague)
- `Fix the bug that was causing issues in the staging environment when deploying` (too long)
- `feat: stuff` (not descriptive)

## Step 5: Generate PR Description

Use the following Markdown template. Fill in each section based on your analysis
from Step 3. Remove sections that are not applicable — do NOT leave empty sections.

```markdown
## What

<!-- One or two sentences explaining WHAT this PR does. Be concise. -->

## Why

<!-- WHY is this change needed? Link to issues, incidents, or context. -->

## How

<!-- HOW does this change work? Describe the approach, not every line of code. -->

## Changes

<!-- Summarize key changes. Group by area if there are many. -->

<commits>

## Testing

<!-- How was this tested? What should reviewers verify? -->

## Notes

<!-- Anything reviewers should know: breaking changes, migration steps,
     follow-up work needed, etc. Remove this section if not applicable. -->
```

### Description Guidelines

- **What/Why/How**: Write for a reviewer who has NO context. Be clear and concise.
- **Changes**: List the meaningful changes. Don't just dump the commit log — group and summarize.
- **`<commits>`**: Replace this tag with the actual commit list from Step 3 inside a collapsible section:
  ```markdown
  <details>
  <summary>Commits</summary>

  - feat(auth): add OAuth2 provider config (a1b2c3d)
  - fix(auth): handle token refresh edge case (d4e5f6a)
  - test(auth): add integration tests for OAuth2 flow (b7c8d9e)

  </details>
  ```
- **Testing**: Be specific. "Tested locally" is not enough. Mention what you verified.
- **Notes**: Include breaking changes, required migrations, or follow-up tasks.

## Step 6: Create or Update the PR

```sh
if [ -n "$EXISTING_PR" ]; then
  # PR already exists — update the description
  gh pr edit "$EXISTING_PR" \
    --title "<generated_title>" \
    --body "<generated_body>"
  echo "Updated PR #$EXISTING_PR"
else
  # Create new PR
  gh pr create \
    --title "<generated_title>" \
    --body "<generated_body>" \
    --base "$DEFAULT_BRANCH"
  echo "Created new PR"
fi
```

## Step 7: Post-Creation Verification

```sh
# Display the PR URL for confirmation
gh pr view --web 2>/dev/null || gh pr view
```

## Important Reminders

- NEVER force-push or rewrite history on shared branches without confirmation
- NEVER create a PR targeting a non-default branch unless explicitly asked
- NEVER include secrets, tokens, or credentials in commit messages or PR descriptions
- NEVER add `Co-Authored-By` or `Generated with` trailers to commit messages or PR descriptions
- If the diff is very large (>1000 lines), suggest splitting into smaller PRs
- If you're unsure about the scope or intent, ASK the user before creating the PR
