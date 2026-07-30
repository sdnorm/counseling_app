# Local CI + gh-signoff as the merge gate

**Date:** 2026-07-30
**Status:** Approved

## Goal

Make `bin/ci` the single CI workflow (run locally), and use
[basecamp/gh-signoff](https://github.com/basecamp/gh-signoff) as the only
required check on PRs. Remove cloud CI entirely.

## Current state

- `bin/ci` already exists (Rails 8.1 `ActiveSupport::ContinuousIntegration`)
  with steps in `config/ci.rb`: setup, unit/integration tests, system tests,
  RuboCop, bundler-audit, importmap audit, Brakeman, then `gh signoff` on
  success.
- The `gh-signoff` extension is installed locally.
- `.github/workflows/ci.yml` duplicates the lint/security steps in Actions.
- No branch protection exists on `main`.

## Changes

1. **`bin/ci` / `config/ci.rb`: no changes.** Already complete. The
   `test:system` step stays — it is a no-op today (empty `test/system/`) and
   activates automatically if system tests are added later.

2. **Delete `.github/workflows/ci.yml`.** Cloud CI is replaced by local
   `bin/ci` + signoff.

3. **Edit `.github/dependabot.yml`:** remove the `github-actions` ecosystem
   block (no workflows remain to update). Keep the `bundler` block.

4. **Repo settings (one-time, run from the repo):**

   ```
   gh signoff install
   ```

   Creates branch protection on `main` requiring the `signoff` status check
   via the API. The manual UI route is avoided because the `signoff` check
   does not appear in the status-check picker until one has been pushed.

## Tradeoffs

- Dependabot PRs no longer merge on their own: nothing in the cloud produces
  a `signoff` status. Each bump requires checking out the branch, running
  `bin/ci` (which signs off on success), then merging.

## Verification

- `bin/ci` runs green locally end to end and pushes a `signoff` status.
- A PR without signoff shows merging blocked; after `bin/ci` passes on the
  branch, merging is allowed.
- No workflows remain under `.github/workflows/`.
