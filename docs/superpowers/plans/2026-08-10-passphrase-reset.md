# Passphrase Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a logged-in user who forgot their passphrase reset it from the unlock screen — keeping their data when the device still holds it, wiping the server blob (with explicit warning) when it doesn't.

**Architecture:** One new password-gated endpoint (`POST /api/sync/reset`) that replaces or deletes the `EncryptedBlob`; the unlock overlay gains a reset panel; `sync_controller.js` re-keys locally (new salt → `deriveKey` → `encrypt` → upload ciphertext) so the server never sees plaintext or the passphrase. Spec: `docs/superpowers/specs/2026-08-10-passphrase-reset-design.md`.

**Tech Stack:** Rails 8 (minitest, `rate_limit`), Stimulus via importmap, WebCrypto (existing `vendor/javascript/lib/crypto.js` / `db.js`). No JS test harness — client behavior is pinned by static "contract tests" (see `test/integration/client_unlock_contract_test.rb` for the pattern) plus manual verification.

**Conventions:** Tests run with `bin/rails test <path>`. Fixtures `users(:danny)` / `users(:maria)` both have password `"password"`; `sign_in_as user` logs in via POST /session. Test env cache is `:null_store`, so `rate_limit` never triggers in tests (the login limiter is untested for the same reason) — the reset limiter is declared in code, asserted only for wiring by eye, and verified manually.

---

### Task 1: Server — `POST /api/sync/reset`

**Files:**
- Modify: `config/routes.rb:6-11` (api namespace)
- Modify: `app/controllers/api/sync_controller.rb`
- Test: `test/controllers/api/sync_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

Append inside the class in `test/controllers/api/sync_controller_test.rb`:

```ruby
  # --- passphrase reset ---

  test "reset with the correct password and a blob replaces the encrypted blob" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "old", nonce: "n", salt: "s")
    sign_in_as user

    post reset_api_sync_path, params: {
      password: "password",
      blob: { ciphertext: "new", nonce: "n2", salt: "s2" }
    }, as: :json

    assert_response :success
    blob = user.reload.encrypted_blob
    assert_equal "new", blob.ciphertext
    assert_equal "s2", blob.salt
  end

  test "reset with the correct password and a blob works when no blob exists yet" do
    user = users(:maria)
    sign_in_as user

    post reset_api_sync_path, params: {
      password: "password",
      blob: { ciphertext: "new", nonce: "n2", salt: "s2" }
    }, as: :json

    assert_response :success
    assert_equal "new", user.reload.encrypted_blob.ciphertext
  end

  test "reset without a blob deletes the encrypted blob" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "old", nonce: "n", salt: "s")
    sign_in_as user

    post reset_api_sync_path, params: { password: "password" }, as: :json

    assert_response :success
    assert_nil user.reload.encrypted_blob
  end

  test "reset without a blob succeeds even when there is nothing to delete" do
    sign_in_as users(:maria)

    post reset_api_sync_path, params: { password: "password" }, as: :json

    assert_response :success
  end

  test "reset with a wrong password changes nothing and says so" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "old", nonce: "n", salt: "s")
    sign_in_as user

    post reset_api_sync_path, params: {
      password: "wrong",
      blob: { ciphertext: "new", nonce: "n2", salt: "s2" }
    }, as: :json

    assert_response :unauthorized
    assert_equal "old", user.reload.encrypted_blob.ciphertext
    assert_includes response.parsed_body["errors"], "Incorrect password"
  end

  test "reset with a wrong password and no blob does not delete anything" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "old", nonce: "n", salt: "s")
    sign_in_as user

    post reset_api_sync_path, params: { password: "wrong" }, as: :json

    assert_response :unauthorized
    assert_not_nil user.reload.encrypted_blob
  end

  test "reset with an invalid blob is rejected without touching the old blob" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "old", nonce: "n", salt: "s")
    sign_in_as user

    post reset_api_sync_path, params: {
      password: "password",
      blob: { ciphertext: "", nonce: "n2", salt: "s2" }
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "old", user.reload.encrypted_blob.ciphertext
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/api/sync_controller_test.rb`
Expected: the seven new tests error with `NameError: undefined local variable or method 'reset_api_sync_path'` (route doesn't exist); existing tests still pass.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, change the sync line inside `namespace :api`:

```ruby
    resource :sync, only: [ :show, :update ], controller: "sync" do
      post :reset
    end
```

- [ ] **Step 4: Implement the action**

In `app/controllers/api/sync_controller.rb`:

1. Add a second `rate_limit` declaration under the existing one. Password guessing through reset must be no faster than through login (`SessionsController#create` allows 10 / 3 minutes):

```ruby
  # Reset verifies the account password, so throttle it like login — this
  # endpoint must not let anyone guess passwords faster than /session does.
  rate_limit to: 10, within: 3.minutes,
    by: -> { current_user&.id || request.remote_ip },
    only: :reset,
    with: -> { render json: { errors: [ "Too many attempts" ] }, status: :too_many_requests }
```

2. Rewrite `update` and add `reset`, sharing the save path (`update`'s current body becomes `save_blob`):

```ruby
  def update
    save_blob
  end

  # Forgot-passphrase reset, gated by the account password. With a blob the
  # client is re-keying (it re-encrypted its local state under a new
  # passphrase); without one there is nothing local to re-key, so the backup
  # is deleted and the user starts over. Either way the server only ever
  # touches ciphertext.
  def reset
    unless current_user.authenticate(params[:password].to_s)
      return render json: { errors: [ "Incorrect password" ] }, status: :unauthorized
    end

    if params[:blob].present?
      save_blob
    else
      current_user.encrypted_blob&.destroy
      render json: { success: true }
    end
  end

  private

  def save_blob
    blob = current_user.encrypted_blob || current_user.build_encrypted_blob
    if blob.update(blob_params)
      render json: { success: true }
    else
      render json: { errors: blob.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def blob_params
    params.require(:blob).permit(:ciphertext, :nonce, :salt)
  end
```

(`blob_params` already exists — keep it; only `save_blob` is new. `current_user.authenticate` is bcrypt's `has_secure_password` check; `.to_s` guards a missing param.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/api/sync_controller_test.rb`
Expected: all pass, including the pre-existing ones.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/api/sync_controller.rb test/controllers/api/sync_controller_test.rb
git commit -m "feat: password-gated passphrase reset endpoint"
```

---

### Task 2: Lockdown regression — reset requires authentication

**Files:**
- Test: `test/integration/authentication_lockdown_test.rb:19-25`

- [ ] **Step 1: Extend the sync api test**

In `test/integration/authentication_lockdown_test.rb`, inside `test "sync api requires authentication"`, append after the PUT assertion:

```ruby
    post reset_api_sync_path, params: { password: "password" }, as: :json
    assert_response :unauthorized
```

- [ ] **Step 2: Run it — should already pass** (authentication is a default `before_action`; this pins it)

Run: `bin/rails test test/integration/authentication_lockdown_test.rb`
Expected: PASS. If it fails, the endpoint is reachable without a session — stop and fix Task 1.

- [ ] **Step 3: Commit**

```bash
git add test/integration/authentication_lockdown_test.rb
git commit -m "test: pin /api/sync/reset behind authentication"
```

---

### Task 3: Defense-in-depth — `no-store` on API responses

Follow-up from the #29–#31 verification: nothing sets `Cache-Control` on `/api` JSON, leaving browser heuristic caching as the last conceivable way a stale account/blob response could reach an unlock or reset. Close it at the base controller.

**Files:**
- Modify: `app/controllers/api/base_controller.rb`
- Test: `test/controllers/api/sync_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Append to `test/controllers/api/sync_controller_test.rb`:

```ruby
  test "api responses are never cacheable" do
    sign_in_as users(:danny)

    get api_sync_path, headers: { "Accept" => "application/json" }

    assert_equal "no-store", response.headers["Cache-Control"],
      "a cached /api/sync response could hand a fresh account another account's blob or salt"
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/controllers/api/sync_controller_test.rb`
Expected: FAIL — Cache-Control is Rails' default (`max-age=0, private, must-revalidate` or absent), not `no-store`.

- [ ] **Step 3: Implement**

Replace `app/controllers/api/base_controller.rb`:

```ruby
class Api::BaseController < ApplicationController
  # Every /api response names an account or carries its blob. no-store keeps
  # any cache — browser heuristics included — from replaying one account's
  # response into another account's unlock or reset.
  after_action :forbid_caching

  private

  def forbid_caching
    response.headers["Cache-Control"] = "no-store"
  end
end
```

(`after_action`, not `before_action`: Rails would overwrite a pre-render header with its own default during render.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/api/`
Expected: all pass (push controller inherits the header too — no assertions there conflict).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/base_controller.rb test/controllers/api/sync_controller_test.rb
git commit -m "fix: mark every /api response no-store"
```

---

### Task 4: Unlock overlay markup — forgot link + reset panel

**Files:**
- Modify: `app/views/layouts/application.html.erb:26-39` (inside the `unlock-overlay` div)

No automated test (static ERB inside an `authenticated?` guard; behavior is covered by Task 6's contract tests and manual verification).

- [ ] **Step 1: Give the existing unlock card an id**

Line 29: change `<div class="card">` to `<div class="card" id="unlock-card">`.

- [ ] **Step 2: Replace the dead-end footer and add the reset card**

Replace the footer paragraph (lines 36–38, "Forgot your passphrase? Your data cannot be recovered. Contact your counselor for a new account.") and add the hidden reset card, so the block after the unlock card reads:

```erb
          <div class="card" id="reset-card" style="display:none;">
            <label class="lbl">Account Password</label>
            <input type="password" id="reset-password" placeholder="Your login password" style="margin-bottom:12px;" />
            <label class="lbl">New Passphrase</label>
            <input type="password" id="reset-passphrase" placeholder="Choose a new passphrase" style="margin-bottom:12px;" />
            <p id="reset-warning-keep" style="color:var(--deep);font-size:12px;margin-bottom:12px;display:none;">Your entries on this device will be kept. Entries made on other devices since this one last synced won't be included.</p>
            <p id="reset-warning-wipe" style="color:#c0392b;font-size:12px;margin-bottom:12px;display:none;">This permanently erases your encrypted backup. Your entries cannot be recovered.</p>
            <button class="btn" id="reset-btn" style="width:100%;">Reset Passphrase</button>
            <p id="reset-error" style="color:#c0392b;font-size:12px;margin-top:8px;display:none;"></p>
            <p style="color:var(--deep);font-size:12px;margin-top:8px;">Write your new passphrase down — it cannot be recovered.</p>
            <p style="text-align:center;font-size:12px;margin-top:12px;"><a href="#" id="reset-back" style="color:var(--blue);text-decoration:underline;">Back</a></p>
          </div>
          <p style="text-align:center;font-size:11px;margin-top:16px;">
            <a href="#" id="unlock-forgot" style="color:var(--lt-brown);text-decoration:underline;">Forgot your passphrase?</a>
          </p>
```

(The reset card sits inside the same `max-width:320px` wrapper, directly after `#unlock-card`. Inline styles match the overlay's existing idiom.)

- [ ] **Step 3: Eyeball it**

Run: `bin/dev`, log in, confirm the unlock screen shows the "Forgot your passphrase?" link and no counselor text. The link does nothing yet.

- [ ] **Step 4: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "feat: reset panel markup on the unlock overlay"
```

---

### Task 5: Client — reset flow in `sync_controller.js`

**Files:**
- Modify: `app/javascript/controllers/sync_controller.js`

- [ ] **Step 1: Wire the three new controls in `showUnlockScreen()`**

At the end of `showUnlockScreen()` (after the `input.onkeydown` assignment), add:

```js
    const forgot = document.getElementById("unlock-forgot");
    if (forgot) forgot.onclick = (e) => { e.preventDefault(); this.openResetPanel(); };
    const back = document.getElementById("reset-back");
    if (back) back.onclick = (e) => { e.preventDefault(); this.closeResetPanel(); };
    const resetBtn = document.getElementById("reset-btn");
    if (resetBtn) resetBtn.onclick = (e) => { e.preventDefault(); this.performReset(); };
```

- [ ] **Step 2: Add `cache: "no-store"` to the existing unlock GET**

In `unlock()`, the `fetch("/api/sync", ...)` options gain `cache: "no-store"` (client half of Task 3):

```js
      const response = await fetch("/api/sync", {
        headers: { "Accept": "application/json" },
        credentials: "same-origin",
        cache: "no-store"
      });
```

- [ ] **Step 3: Add the three new methods** (after `showUnlockScreen()`, before `unlock()`)

```js
  // The reset panel needs to know up front whether this device still holds the
  // account's data: if it does, reset re-keys and loses nothing; if not, reset
  // can only wipe the backup. The warning shown must match the path taken.
  async openResetPanel() {
    const error = document.getElementById("unlock-error");
    try {
      const response = await fetch("/api/sync", {
        headers: { "Accept": "application/json" },
        credentials: "same-origin",
        cache: "no-store"
      });
      if (response.status === 401) {
        error.innerHTML = 'Session expired. <a href="/session/new" style="color:var(--blue);text-decoration:underline;">Log in again</a>.';
        error.style.display = "block";
        return;
      }
      this.resetAccount = (await response.json().catch(() => ({}))).account;
    } catch (e) {
      console.error("Reset unavailable:", e);
      error.textContent = "Reset needs a connection. Please try again.";
      error.style.display = "block";
      return;
    }

    const stamp = await readAccountStamp();
    this.resetKeepsData = stamp !== null && stamp === this.resetAccount;

    document.getElementById("reset-warning-keep").style.display = this.resetKeepsData ? "block" : "none";
    document.getElementById("reset-warning-wipe").style.display = this.resetKeepsData ? "none" : "block";
    document.getElementById("reset-password").value = "";
    document.getElementById("reset-passphrase").value = "";
    document.getElementById("reset-error").style.display = "none";
    error.style.display = "none";
    document.getElementById("unlock-card").style.display = "none";
    document.getElementById("reset-card").style.display = "block";
  }

  closeResetPanel() {
    document.getElementById("reset-card").style.display = "none";
    document.getElementById("unlock-card").style.display = "block";
  }

  async performReset() {
    const password = document.getElementById("reset-password").value;
    const passphrase = document.getElementById("reset-passphrase").value;
    const error = document.getElementById("reset-error");
    if (!password || !passphrase) return;
    error.style.display = "none";

    try {
      const body = { password };
      let salt = null;
      let key = null;

      if (this.resetKeepsData) {
        // Re-key: encrypt the state this device already holds under the new
        // passphrase. Only ciphertext leaves the device, same as every save.
        const { exportState } = await import("lib/db");
        const { encrypt } = await import("lib/crypto");
        salt = window.crypto.getRandomValues(new Uint8Array(16));
        key = await deriveKey(passphrase, salt);
        const state = await exportState();
        const { ciphertext, nonce } = await encrypt(state, key);
        body.blob = { ciphertext, nonce, salt: btoa(String.fromCharCode(...salt)) };
      }

      const response = await fetch("/api/sync/reset", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        credentials: "same-origin",
        body: JSON.stringify(body)
      });

      if (response.status === 401) {
        // Our action's wrong-password 401 carries an errors body; the
        // authentication concern's session-expired 401 is an empty head.
        const data = await response.json().catch(() => null);
        if (data && data.errors) {
          error.textContent = "Incorrect password. Please try again.";
        } else {
          error.innerHTML = 'Session expired. <a href="/session/new" style="color:var(--blue);text-decoration:underline;">Log in again</a>.';
        }
        error.style.display = "block";
        return;
      }
      if (response.status === 429) {
        error.textContent = "Too many attempts. Please try again later.";
        error.style.display = "block";
        return;
      }
      if (!response.ok) {
        error.textContent = "Reset failed. Please try again.";
        error.style.display = "block";
        return;
      }

      if (!this.resetKeepsData) {
        // Start-over path, only after the server confirmed the old backup is
        // gone: same first-run behavior as a 404 unlock.
        await this.discardOtherAccountData(this.resetAccount);
        salt = window.crypto.getRandomValues(new Uint8Array(16));
        key = await deriveKey(passphrase, salt);
      }

      this.salt = salt;
      this.key = key;
      this.closeResetPanel();
      document.getElementById("unlock-overlay").style.display = "none";
      this.unlocked = true;
      document.dispatchEvent(new CustomEvent("app:unlocked", { bubbles: true }));
    } catch (e) {
      console.error("Reset failed:", e);
      error.textContent = "Reset failed. Please try again.";
      error.style.display = "block";
    }
  }
```

(`deriveKey`, `readAccountStamp`, and `discardOtherAccountData` are already imported/defined; `exportState`/`encrypt` use the same dynamic imports as `save()`.)

- [ ] **Step 4: Sanity-run the existing static contract tests** (they regex this file; make sure the edits didn't break their anchors)

Run: `bin/rails test test/integration/client_unlock_contract_test.rb test/integration/client_sync_contract_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/sync_controller.js
git commit -m "feat: forgot-passphrase reset flow on the unlock screen"
```

---

### Task 6: Contract test — pin the reset asymmetry

The dangerous regressions are (a) the wipe branch running even though the device held the data, (b) local data being discarded before the server accepted the reset, (c) the re-key branch clearing anything. Pin them statically like `client_unlock_contract_test.rb` does.

**Files:**
- Create: `test/integration/client_reset_contract_test.rb`

- [ ] **Step 1: Write the tests**

```ruby
require "test_helper"

# Passphrase reset has two branches with opposite stakes:
#
#   re-key    — the device holds the data; reset must keep it (encrypt under
#               the new passphrase) and must never clear anything.
#   start-over — the device holds nothing; reset wipes the server backup, so
#               the local discard may only run after the server said yes.
#
# Pinned statically because there is no JS test harness.
class ClientResetContractTest < ActiveSupport::TestCase
  SYNC_CONTROLLER = Rails.root.join("app/javascript/controllers/sync_controller.js")

  def source
    @source ||= SYNC_CONTROLLER.read
  end

  def method_body(name)
    source[/async #{name}\s*\([^)]*\)\s*\{(.+?)\n  \}/m, 1]
  end

  test "the branch choice comes from comparing the device stamp to the account" do
    body = method_body("openResetPanel")
    assert body, "expected an openResetPanel method in sync_controller.js"
    assert_match(/stamp\s*!==\s*null\s*&&\s*stamp\s*===\s*this\.resetAccount/, body,
      "re-keying is only safe when a stamp proves the local data belongs to " \
      "the account being reset")
  end

  test "the re-key branch encrypts local state and never clears it" do
    body = method_body("performReset")
    assert body, "expected a performReset method in sync_controller.js"

    keep = body[/if\s*\(this\.resetKeepsData\)\s*\{(.*?)\n      \}/m, 1]
    assert keep, "expected a resetKeepsData branch that builds the new blob"
    assert_match(/exportState/, keep, "re-key must upload the state the device already holds")
    assert_no_match(/clearData|discardOtherAccountData|importState/, keep,
      "the re-key branch must not touch local data — it is the only copy")
  end

  test "the start-over branch discards local data only after the server accepted" do
    body = method_body("performReset")
    discard_at = body.index("discardOtherAccountData")
    ok_check_at = body.index("!response.ok")
    assert discard_at, "expected the start-over branch to run the first-time discard"
    assert ok_check_at, "expected reset to bail out on a non-ok response"
    assert ok_check_at < discard_at,
      "local data must never be discarded before the server confirmed the reset: " \
      "a failed reset must leave the device exactly as it was"
  end

  test "reset uploads only ciphertext" do
    body = method_body("performReset")
    assert_match(/blob\s*=\s*\{\s*ciphertext,\s*nonce,\s*salt:/, body,
      "the reset payload must be the encrypted blob shape — plaintext state " \
      "must never be posted")
    assert_no_match(/body\.state|plaintext/, body,
      "no unencrypted state may appear in the reset request body")
  end
end
```

- [ ] **Step 2: Run the tests to verify they pass against Task 5's code**

Run: `bin/rails test test/integration/client_reset_contract_test.rb`
Expected: PASS. If a regex fails to match, fix the regex to match Task 5's actual code — do not weaken the assertions' meaning.

- [ ] **Step 3: Break it on purpose, watch it fail, restore**

Temporarily reorder: move the `discardOtherAccountData` call above the `!response.ok` check in `performReset`, run the test, expect the third test to FAIL. Revert the change (`git checkout app/javascript/controllers/sync_controller.js` is safe — Task 5 is committed).

- [ ] **Step 4: Commit**

```bash
git add test/integration/client_reset_contract_test.rb
git commit -m "test: pin the passphrase-reset keep/wipe asymmetry"
```

---

### Task 7: Full verification

- [ ] **Step 1: Run the whole suite**

Run: `bin/ci`
Expected: green (tests, rubocop, brakeman, bundler-audit). Fix anything it flags before proceeding.

- [ ] **Step 2: Manual verification in the browser** (`bin/dev`)

1. **Re-key path:** log in, unlock with a known passphrase, add a journal entry. Reload → "Forgot your passphrase?" → panel shows the *keep* warning. Enter account password + a new passphrase → unlocked, entry still there. Reload, unlock with the **new** passphrase → works; old passphrase → "Incorrect passphrase."
2. **Wrong password:** reset panel, wrong account password → "Incorrect password," entries untouched, still locked.
3. **Wipe path:** in devtools, delete the IndexedDB database (simulates a fresh device), reload → reset panel shows the *wipe* warning. Reset → first-time state, server blob gone (GET /api/sync → 404).
4. **Rate limit:** submit a wrong password 11 times quickly → "Too many attempts." (Dev uses `:memory_store`, so the limiter is live there.)
5. **Headers:** devtools Network tab → `/api/sync` response has `Cache-Control: no-store`.

- [ ] **Step 3: Report**

Summarize results (including anything that deviated) before merging. Branch: `lost-passphrase`; ship as a PR to `main` per repo guardrails.
