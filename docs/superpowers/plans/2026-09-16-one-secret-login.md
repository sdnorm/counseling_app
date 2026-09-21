# One-Secret Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the password-plus-passphrase login with a single password from which the browser derives an auth hash and a key-wrapping key, plus a recovery code, without the server ever seeing a password or a data key.

**Architecture:** A random data key encrypts the journal blob. The browser wraps that key twice (under a password-derived key and a recovery-code-derived key) and the server stores only the wrapped copies plus a bcrypt of a one-way auth hash. Login, signup, reset, and settings are Stimulus controllers that do the derivation and talk JSON to Rails; app boot reads the data key from IndexedDB and decrypts.

**Tech Stack:** Rails 8.1, SQLite, `has_secure_password`, Stimulus via importmap, Web Crypto API (PBKDF2, HKDF, AES-GCM, wrapKey/unwrapKey), IndexedDB, Minitest.

**Spec:** `docs/superpowers/specs/2026-09-16-one-secret-login-design.md`

---

## How this plan is executed

Work is split into lanes. Every agent works in this same checkout on the
`product-ready` branch (Herdr workspace `wM`, one tab per agent). Lanes never
edit the same file, and each agent stages and commits only the files its lane
owns, one commit per task: `git add <its files> && git commit -m "..."` in a
single command. If `git commit` reports `index.lock`, another agent is
committing: wait a few seconds and retry. Never run `git stash`, never
`git add -A`, never push. The driver (Claude, tab 1) does the Foundation
first, then prompts the lanes, then integrates.

| Lane | Agent | Owns |
|---|---|---|
| Foundation | driver | migrations, `db/schema.rb`, `app/models/user.rb`, `app/models/encrypted_blob.rb`, `test/models/**`, `test/fixtures/users.yml`, `test/test_helper.rb`, mechanical updates to existing tests |
| S — server | pi | `app/controllers/**`, `config/routes.rb`, `test/controllers/**`, `test/integration/authentication_lockdown_test.rb`, `test/integration/password_reset_security_test.rb` |
| K — client auth | codex | `vendor/javascript/lib/keys.js`, `vendor/javascript/lib/request.js`, `vendor/javascript/lib/db.js`, `vendor/javascript/lib/crypto.js`, `app/javascript/controllers/{signup,login,password_reset,recovery_code}_controller.js`, `app/views/{sessions,users,passwords}/**`, `app/views/shared/_recovery_code.html.erb`, `app/assets/stylesheets/application.css`, `test/integration/client_keys_contract_test.rb` |
| A — app shell | grok | `app/javascript/controllers/{sync,logout,account}_controller.js`, `vendor/javascript/lib/session.js`, `app/views/layouts/application.html.erb`, `app/views/screens/settings.html.erb`, `test/integration/client_boot_contract_test.rb`, deletion of `client_unlock_contract_test.rb` and `client_reset_contract_test.rb` |

Lanes S, K, and A run in parallel once the Foundation is committed. Lane A
imports functions Lane K writes; because they share a checkout, A sees K's
files as soon as they land, and A's tests are static so nothing blocks.

## Contract between lanes

### `vendor/javascript/lib/keys.js` (Lane K writes, Lane A uses)

```js
export const MIN_PASSWORD_LENGTH = 12;
export const PBKDF2_ROUNDS = 600000;
export function normalizeEmail(email)                        // -> string
export function generateRecoveryCode()                       // -> "XXXX-XXXX-XXXX-XXXX-XXXX"
export function normalizeRecoveryCode(input)                 // -> "XXXXXXXXXXXXXXXXXXXX"
export async function derivePasswordKeys(password, email)    // -> { wrappingKey: CryptoKey, authHash: string(43) }
export async function deriveRecoveryWrappingKey(code, email) // -> CryptoKey
export async function generateDataKey()                      // -> extractable AES-GCM CryptoKey
export async function wrapDataKey(dataKey, wrappingKey)      // -> JSON string {"nonce","ciphertext"}
export async function unwrapDataKey(json, wrappingKey, { extractable = false } = {}) // -> CryptoKey; throws on wrong key
export async function lockDataKey(extractableKey)            // -> non-extractable copy
```

### `vendor/javascript/lib/request.js` (Lane K writes, Lane A uses)

```js
export async function requestJSON(method, url, body) // -> { ok, status, data }
```

### `vendor/javascript/lib/db.js` additions (Lane K writes, Lane A uses)

```js
export async function readDataKey()      // -> CryptoKey | null
export async function writeDataKey(key)  // -> void
```

### Server JSON (Lane S writes, Lanes K and A use)

| Request | Success | Failure |
|---|---|---|
| `POST /session` `{ email_address, password }` | `200 { account, password_wrapped_key }` | `401 { errors }`, `429 { errors }` |
| `POST /users` `{ user: { email_address, password, invite_code, password_wrapped_key, recovery_wrapped_key } }` | `201 { account }` | `422 { errors }` |
| `GET /api/account/keys` | `200 { password_wrapped_key, recovery_wrapped_key }` | `401` |
| `PUT /api/account/keys` `{ current_password, password?, password_wrapped_key?, recovery_wrapped_key? }` | `200 {}` | `401 { errors }` wrong current password, `422 { errors }` |
| `PATCH /passwords/:token` `{ password, password_wrapped_key, recovery_wrapped_key, blob?: { ciphertext, nonce }, wipe?: true }` | `200 { account }` and a new session cookie | `422 { errors }` |
| `GET /api/sync` | unchanged | unchanged |
| `PUT /api/sync` `{ blob: { ciphertext, nonce } }` | unchanged | unchanged |

`password` and `current_password` are always the 43-character auth hash.
`account` is the user id, used as the IndexedDB account stamp.

### Page data attributes (Lane K writes)

`app/views/passwords/edit.html.erb` root element carries
`data-password-reset-account-value`, `data-password-reset-email-value`,
`data-password-reset-recovery-wrapped-key-value`, and
`data-password-reset-token-value`.

`app/views/sessions/new.html.erb` shows "Your password was changed on
another device. Sign in again." when `params[:reason] == "changed"`. Lane A
redirects there.

---

## Foundation (driver, on `product-ready`)

### Task F1: Launch migration and wrapped-key columns

**Files:**
- Create: `db/migrate/20260916000001_clear_client_accounts_for_one_secret_login.rb`
- Create: `db/migrate/20260916000002_add_wrapped_keys_to_users.rb`

- [ ] **Step 1: Write the clearing migration**

```ruby
# db/migrate/20260916000001_clear_client_accounts_for_one_secret_login.rb
class ClearClientAccountsForOneSecretLogin < ActiveRecord::Migration[8.1]
  # One-secret login has no migration path from password + passphrase
  # accounts. Launch starts fresh: the counselor re-invites every client.
  def up
    execute "DELETE FROM sessions"
    execute "DELETE FROM push_subscriptions"
    execute "DELETE FROM encrypted_blobs"
    execute "DELETE FROM users"
    execute "DELETE FROM invite_codes"
  end

  def down
    # Deleted rows are gone; nothing to restore.
  end
end
```

- [ ] **Step 2: Write the columns migration**

```ruby
# db/migrate/20260916000002_add_wrapped_keys_to_users.rb
class AddWrappedKeysToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_wrapped_key, :text, null: false
    add_column :users, :recovery_wrapped_key, :text, null: false
    change_column_null :encrypted_blobs, :salt, true
  end
end
```

- [ ] **Step 3: Run migrations and check the schema**

Run: `bin/rails db:migrate && grep -n 'wrapped_key\|"salt"' db/schema.rb`
Expected: two `t.text "..._wrapped_key", null: false` lines under `users`; `t.string "salt"` under `encrypted_blobs` with no `null: false`.

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "Clear client accounts and add wrapped data-key columns for one-secret login"
```

### Task F2: User and EncryptedBlob validations

**Files:**
- Modify: `app/models/user.rb`
- Modify: `app/models/encrypted_blob.rb`
- Modify: `test/models/user_test.rb`
- Modify: `test/models/encrypted_blob_test.rb`

- [ ] **Step 1: Write failing model tests**

Append to `test/models/user_test.rb` (create the class if the file is empty):

```ruby
  test "password must be an auth hash, never a raw password" do
    user = User.new(email_address: "k@example.com", invite_code: invite_codes(:danny_invite),
      password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY)

    user.password = "correct horse battery staple"
    assert_not user.valid?
    assert_includes user.errors[:password], "requires JavaScript to be enabled"

    user.password = AUTH_HASH
    assert user.valid?, user.errors.full_messages.to_sentence
  end

  test "wrapped keys are required and bounded" do
    user = User.new(email_address: "k@example.com", invite_code: invite_codes(:danny_invite), password: AUTH_HASH)
    assert_not user.valid?
    assert_includes user.errors[:password_wrapped_key], "can't be blank"
    assert_includes user.errors[:recovery_wrapped_key], "can't be blank"

    user.password_wrapped_key = "x" * (User::WRAPPED_KEY_MAX_BYTES + 1)
    user.recovery_wrapped_key = WRAPPED_KEY
    assert_not user.valid?
    assert_includes user.errors[:password_wrapped_key], "is too long (maximum is #{User::WRAPPED_KEY_MAX_BYTES} characters)"
  end
```

Replace `test "rejects oversized nonce and salt"` in `test/models/encrypted_blob_test.rb` with:

```ruby
  test "rejects an oversized nonce" do
    assert_not build_blob(nonce: "n" * 200).valid?
  end

  test "salt is optional" do
    assert build_blob(salt: nil).valid?
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/models/user_test.rb test/models/encrypted_blob_test.rb`
Expected: FAIL (`AUTH_HASH` undefined, `WRAPPED_KEY_MAX_BYTES` undefined, salt presence error).

- [ ] **Step 3: Update the models**

`app/models/user.rb`, replace the `MINIMUM_PASSWORD_LENGTH` constant and the password validation:

```ruby
class User < ApplicationRecord
  # The client sends a 32-byte HKDF output, base64url without padding. A raw
  # password can only arrive if the browser's JavaScript never ran.
  AUTH_HASH_FORMAT = /\A[A-Za-z0-9_-]{43}\z/
  WRAPPED_KEY_MAX_BYTES = 256

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :encrypted_blob, dependent: :destroy
  include PushNotifiable
  belongs_to :invite_code

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  encrypts :email_address, deterministic: true

  # Deterministic encryption keeps this uniqueness check queryable. Without it a
  # duplicate email hits the unique index and 500s instead of re-rendering the form.
  validates :email_address, presence: true,
    uniqueness: { message: "already has an account — sign in or reset your password below" }

  # allow_nil so updates that don't touch the password (reminder settings, the
  # reminder job's timestamp) skip this entirely.
  validates :password, format: { with: AUTH_HASH_FORMAT, message: "requires JavaScript to be enabled" }, allow_nil: true

  validates :password_wrapped_key, :recovery_wrapped_key,
    presence: true, length: { maximum: WRAPPED_KEY_MAX_BYTES }
```

Keep everything from `normalizes :reminder_time` down unchanged.

`app/models/encrypted_blob.rb`, replace the validations block:

```ruby
  belongs_to :user
  validates :ciphertext, :nonce, presence: true
  validates :ciphertext, length: { maximum: MAX_CIPHERTEXT_BYTES }
  validates :nonce, length: { maximum: MAX_NONCE_BYTES }
  # Legacy column: the client no longer sends it. Bounded so it can't be abused.
  validates :salt, length: { maximum: MAX_SALT_BYTES }, allow_nil: true
```

- [ ] **Step 4: Add test constants and fixtures**

`test/test_helper.rb`, add after `require "minitest/mock"`:

```ruby
# What the browser sends as the "password": a 43-char base64url auth hash.
AUTH_HASH = "a" * 43
NEW_AUTH_HASH = "b" * 43
WRAPPED_KEY = '{"nonce":"bm9uY2U=","ciphertext":"Y2lwaGVy"}'
```

Change `sign_in_as`:

```ruby
class ActionDispatch::IntegrationTest
  def sign_in_as(user, password: AUTH_HASH)
    post session_path, params: { email_address: user.email_address, password: password }
  end
end
```

`test/fixtures/users.yml`:

```yaml
danny:
  email_address: danny@example.com
  password_digest: <%= BCrypt::Password.create("a" * 43) %>
  invite_code: danny_invite
  password_wrapped_key: '{"nonce":"bm9uY2U=","ciphertext":"Y2lwaGVy"}'
  recovery_wrapped_key: '{"nonce":"bm9uY2U=","ciphertext":"cmVjb3Zlcnk="}'

maria:
  email_address: maria@example.com
  password_digest: <%= BCrypt::Password.create("a" * 43) %>
  invite_code: maria_invite
  password_wrapped_key: '{"nonce":"bm9uY2U=","ciphertext":"Y2lwaGVy"}'
  recovery_wrapped_key: '{"nonce":"bm9uY2U=","ciphertext":"cmVjb3Zlcnk="}'
```

- [ ] **Step 5: Run the model tests**

Run: `bin/rails test test/models`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/models test/models test/fixtures/users.yml test/test_helper.rb
git commit -m "Validate auth-hash passwords and wrapped keys on User"
```

### Task F3: Keep existing tests green under the new model

These edits are mechanical. Lane S rewrites most of these files later; the
point here is a green baseline for every lane.

**Files:**
- Modify: `test/controllers/users_controller_test.rb`
- Modify: `test/controllers/api/sync_controller_test.rb`
- Modify: `test/integration/password_reset_security_test.rb`
- Modify: `app/views/passwords/edit.html.erb` (one line)

- [ ] **Step 1: Run the whole suite to see what breaks**

Run: `bin/rails test`
Expected: failures in the three files above (raw passwords rejected; `MINIMUM_PASSWORD_LENGTH` missing in `passwords/edit`).

- [ ] **Step 2: Fix `users_controller_test.rb`**

Replace every `password: "supersecret1", password_confirmation: "supersecret1"` with
`password: NEW_AUTH_HASH, password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY`.
Replace every `password: "short", password_confirmation: "short"` with
`password: "short", password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY`.
In `"a rejected signup tells the user why"` change `assert_match(/too short/i, ...)` to `assert_match(/requires JavaScript/i, ...)`.
In `"a duplicate email that slips past validation..."` change the `User.new(...)` to:

```ruby
    user = User.new(email_address: "race@example.com", password: NEW_AUTH_HASH,
      password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY)
```

- [ ] **Step 3: Fix `sync_controller_test.rb`**

Replace every `password: "password"` with `password: AUTH_HASH`. Leave the reset tests in place; Lane S deletes them with the endpoint.

- [ ] **Step 4: Fix `password_reset_security_test.rb`**

Replace `"password"` in `authenticate_by` with `AUTH_HASH`, and both `"newpassword123"` with `NEW_AUTH_HASH`, and `"different123"` with `AUTH_HASH`.

- [ ] **Step 5: Fix `passwords/edit.html.erb`**

Change the subtitle line to `<p class="subtitle">Choose a password of at least 12 characters.</p>` (Lane K rewrites this view fully).

- [ ] **Step 6: Run the whole suite**

Run: `bin/rails test && bin/rubocop`
Expected: `0 failures, 0 errors`, rubocop clean.

- [ ] **Step 7: Commit**

```bash
git add test app/views/passwords/edit.html.erb
git commit -m "Update existing tests for auth-hash passwords"
```

---

## Lane S — server (pi)

Run `bin/rails test` after every task. Only touch the files listed. Do not
edit views under `app/views/sessions`, `app/views/users`, or
`app/views/passwords` (Lane K owns them); pass data to views through
instance variables only.

### Task S1: Sessions respond to JSON

**Files:**
- Modify: `app/controllers/sessions_controller.rb`
- Create: `test/controllers/sessions_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/sessions_controller_test.rb
require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "JSON login returns the account and the password-wrapped data key" do
    user = users(:danny)

    post session_path, params: { email_address: user.email_address, password: AUTH_HASH }, as: :json

    assert_response :success
    assert_equal user.id, response.parsed_body["account"]
    assert_equal user.password_wrapped_key, response.parsed_body["password_wrapped_key"]
    assert_nil response.parsed_body["recovery_wrapped_key"],
      "login must not hand out the recovery-wrapped copy"
  end

  test "JSON login with a wrong auth hash is 401 with an error" do
    post session_path, params: { email_address: users(:danny).email_address, password: NEW_AUTH_HASH }, as: :json

    assert_response :unauthorized
    assert_equal [ "Try another email address or password." ], response.parsed_body["errors"]
  end

  test "JSON login sets the session cookie" do
    user = users(:danny)
    post session_path, params: { email_address: user.email_address, password: AUTH_HASH }, as: :json

    get screen_path("journal")
    assert_response :success
  end

  test "HTML login still redirects" do
    user = users(:danny)
    post session_path, params: { email_address: user.email_address, password: AUTH_HASH }
    assert_redirected_to root_url

    delete session_path
    post session_path, params: { email_address: user.email_address, password: "wrong" }
    assert_redirected_to new_session_path
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/sessions_controller_test.rb`
Expected: the first three FAIL (JSON login currently redirects; `parsed_body` has no `account`).

- [ ] **Step 3: Implement**

```ruby
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  layout "session", only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { too_many_attempts }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      respond_to do |format|
        format.html { redirect_to after_authentication_url }
        # The browser unwraps this with the key it derived from the password;
        # the server can't open it. The recovery-wrapped copy stays out of
        # login: it only ever leaves on the token-gated reset page.
        format.json { render json: { account: user.id, password_wrapped_key: user.password_wrapped_key } }
      end
    else
      respond_to do |format|
        format.html { redirect_to new_session_path, alert: "Try another email address or password." }
        format.json { render json: { errors: [ "Try another email address or password." ] }, status: :unauthorized }
      end
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private

  def too_many_attempts
    respond_to do |format|
      format.html { redirect_to new_session_path, alert: "Try again later." }
      format.json { render json: { errors: [ "Try again later." ] }, status: :too_many_requests }
    end
  end
end
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/controllers/sessions_controller_test.rb test/integration`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/sessions_controller.rb test/controllers/sessions_controller_test.rb
git commit -m "Return the wrapped data key from JSON login"
```

### Task S2: Signup takes wrapped keys and responds to JSON

**Files:**
- Modify: `app/controllers/users_controller.rb`
- Modify: `test/controllers/users_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/users_controller_test.rb`:

```ruby
  test "JSON signup creates the account with both wrapped keys and returns the account id" do
    code = InviteCode.generate("json@example.com")

    assert_difference -> { User.count }, 1 do
      post users_path, params: { user: {
        email_address: "json@example.com",
        password: NEW_AUTH_HASH,
        invite_code: code.code,
        password_wrapped_key: WRAPPED_KEY,
        recovery_wrapped_key: WRAPPED_KEY
      } }, as: :json
    end

    assert_response :created
    user = User.find_by(email_address: "json@example.com")
    assert_equal user.id, response.parsed_body["account"]
    assert_equal WRAPPED_KEY, user.password_wrapped_key
    assert_equal WRAPPED_KEY, user.recovery_wrapped_key
    assert User.authenticate_by(email_address: "json@example.com", password: NEW_AUTH_HASH)
  end

  test "JSON signup starts a session" do
    code = InviteCode.generate("session@example.com")
    post users_path, params: { user: {
      email_address: "session@example.com", password: NEW_AUTH_HASH, invite_code: code.code,
      password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY
    } }, as: :json

    get screen_path("journal")
    assert_response :success
  end

  test "JSON signup without wrapped keys is rejected and explains why" do
    code = InviteCode.generate("nokeys@example.com")

    assert_no_difference -> { User.count } do
      post users_path, params: { user: {
        email_address: "nokeys@example.com", password: NEW_AUTH_HASH, invite_code: code.code
      } }, as: :json
    end

    assert_response :unprocessable_entity
    assert_match(/wrapped key/i, response.parsed_body["errors"].join)
    assert_not code.reload.used?
  end

  test "JSON signup with a bad invite code is rejected with an error list" do
    post users_path, params: { user: {
      email_address: "bad@example.com", password: NEW_AUTH_HASH, invite_code: "NOPE0000",
      password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY
    } }, as: :json

    assert_response :unprocessable_entity
    assert_equal [ "Invalid or already used invite code." ], response.parsed_body["errors"]
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/users_controller_test.rb`
Expected: the new tests FAIL (JSON create redirects; wrapped keys not permitted).

- [ ] **Step 3: Implement**

```ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  allow_unauthenticated_access only: [ :new, :create ]
  layout "session"
  rate_limit to: 10, within: 10.minutes, only: :create, with: -> { too_many_attempts }

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params.except(:invite_code))

    if claim_code_and_save
      start_new_session_for @user
      respond_to do |format|
        format.html { redirect_to root_path, notice: "Account created successfully." }
        format.json { render json: { account: @user.id }, status: :created }
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:alert] = @error
          render :new, status: :unprocessable_entity
        end
        format.json { render json: { errors: [ @error ] }, status: :unprocessable_entity }
      end
    end
  end

  private

  # Claiming the code and creating the user share one transaction: the claim has
  # to be atomic so concurrent signups can't reuse a code, but a signup we then
  # reject must roll the claim back rather than burn the code.
  def claim_code_and_save
    ActiveRecord::Base.transaction do
      invite_code = InviteCode.claim(user_params[:invite_code])
      if invite_code.nil?
        @error = "Invalid or already used invite code."
        raise ActiveRecord::Rollback
      end

      @user.invite_code = invite_code
      unless @user.save
        @error = @user.errors.full_messages.join(", ")
        raise ActiveRecord::Rollback
      end

      invite_code.update!(user: @user)
      true
    end
  # Backstop for the race where a duplicate email passes validation but loses to
  # the unique index. Rescuing outside the transaction rolls the claim back too.
  rescue ActiveRecord::RecordNotUnique
    @error = "That email address already has an account — sign in or reset your password below."
    false
  end

  def user_params
    params.require(:user).permit(:email_address, :password, :invite_code,
      :password_wrapped_key, :recovery_wrapped_key)
  end

  def too_many_attempts
    respond_to do |format|
      format.html { redirect_to new_user_path, alert: "Too many sign-up attempts. Try again later." }
      format.json { render json: { errors: [ "Too many sign-up attempts. Try again later." ] }, status: :too_many_requests }
    end
  end
end
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/controllers/users_controller_test.rb`
Expected: PASS. (The existing HTML tests still pass because `password_confirmation` is simply no longer permitted.)

- [ ] **Step 5: Commit**

```bash
git add app/controllers/users_controller.rb test/controllers/users_controller_test.rb
git commit -m "Accept wrapped data keys at signup and respond to JSON"
```

### Task S3: Account keys endpoint

**Files:**
- Create: `app/controllers/api/account_keys_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/api/account_keys_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/api/account_keys_controller_test.rb
require "test_helper"

class Api::AccountKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:danny)
    sign_in_as @user
  end

  test "show returns both wrapped keys" do
    get api_account_keys_path, headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal @user.password_wrapped_key, response.parsed_body["password_wrapped_key"]
    assert_equal @user.recovery_wrapped_key, response.parsed_body["recovery_wrapped_key"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "changing the password swaps the auth hash and the password-wrapped key" do
    put api_account_keys_path, params: {
      current_password: AUTH_HASH, password: NEW_AUTH_HASH, password_wrapped_key: '{"nonce":"x","ciphertext":"y"}'
    }, as: :json

    assert_response :success
    @user.reload
    assert User.authenticate_by(email_address: @user.email_address, password: NEW_AUTH_HASH)
    assert_equal '{"nonce":"x","ciphertext":"y"}', @user.password_wrapped_key
  end

  test "changing the password ends every other session but keeps this one" do
    other = @user.sessions.create!(user_agent: "other", ip_address: "10.0.0.1")

    put api_account_keys_path, params: {
      current_password: AUTH_HASH, password: NEW_AUTH_HASH, password_wrapped_key: WRAPPED_KEY
    }, as: :json

    assert_response :success
    assert_nil Session.find_by(id: other.id)
    get screen_path("journal")
    assert_response :success, "the session that changed the password must survive"
  end

  test "rotating the recovery code replaces only the recovery-wrapped key" do
    digest_before = @user.password_digest

    put api_account_keys_path, params: {
      current_password: AUTH_HASH, recovery_wrapped_key: '{"nonce":"r","ciphertext":"s"}'
    }, as: :json

    assert_response :success
    @user.reload
    assert_equal '{"nonce":"r","ciphertext":"s"}', @user.recovery_wrapped_key
    assert_equal digest_before, @user.password_digest
    assert_equal 1, @user.sessions.count
  end

  test "a wrong current password changes nothing" do
    digest_before = @user.password_digest

    put api_account_keys_path, params: {
      current_password: NEW_AUTH_HASH, password: NEW_AUTH_HASH, password_wrapped_key: WRAPPED_KEY
    }, as: :json

    assert_response :unauthorized
    assert_equal [ "Incorrect password" ], response.parsed_body["errors"]
    assert_equal digest_before, @user.reload.password_digest
  end

  test "a raw password is rejected as a new password" do
    put api_account_keys_path, params: {
      current_password: AUTH_HASH, password: "correct horse battery", password_wrapped_key: WRAPPED_KEY
    }, as: :json

    assert_response :unprocessable_entity
    assert_match(/JavaScript/, response.parsed_body["errors"].join)
  end

  test "a request that changes nothing is rejected" do
    put api_account_keys_path, params: { current_password: AUTH_HASH }, as: :json
    assert_response :unprocessable_entity
  end

  test "requires authentication" do
    delete session_path
    put api_account_keys_path, params: { current_password: AUTH_HASH, recovery_wrapped_key: WRAPPED_KEY }, as: :json
    assert_response :unauthorized
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/api/account_keys_controller_test.rb`
Expected: FAIL with `undefined method 'api_account_keys_path'`.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside `namespace :api do`, add:

```ruby
    resource :account_keys, only: [ :show, :update ], path: "account/keys"
```

- [ ] **Step 4: Implement the controller**

```ruby
# app/controllers/api/account_keys_controller.rb
class Api::AccountKeysController < Api::BaseController
  # Update verifies the current auth hash, so throttle it like login: this
  # endpoint must not let anyone guess credentials faster than /session does.
  rate_limit to: 10, within: 3.minutes,
    by: -> { current_user&.id || request.remote_ip },
    only: :update,
    with: -> { render json: { errors: [ "Too many attempts" ] }, status: :too_many_requests }

  def show
    render json: {
      password_wrapped_key: current_user.password_wrapped_key,
      recovery_wrapped_key: current_user.recovery_wrapped_key
    }
  end

  # Change password (password + password_wrapped_key) or rotate the recovery
  # code (recovery_wrapped_key). The data key itself never changes: the
  # browser unwraps it with the old wrapping key and re-wraps under the new
  # one, so the server only ever swaps ciphertext.
  def update
    unless current_user.authenticate(params[:current_password].to_s)
      return render json: { errors: [ "Incorrect password" ] }, status: :unauthorized
    end

    changes = params.permit(:password, :password_wrapped_key, :recovery_wrapped_key).to_h.compact_blank
    if changes.empty?
      return render json: { errors: [ "Nothing to change" ] }, status: :unprocessable_entity
    end

    User.transaction do
      if current_user.update(changes)
        # A new password invalidates every other device's login, but not the
        # one that just proved it knows the current password.
        current_user.sessions.where.not(id: Current.session.id).destroy_all if changes.key?("password")
        render json: {}
      else
        render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
        raise ActiveRecord::Rollback
      end
    end
  end
end
```

- [ ] **Step 5: Run the tests**

Run: `bin/rails test test/controllers/api/account_keys_controller_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/account_keys_controller.rb config/routes.rb test/controllers/api/account_keys_controller_test.rb
git commit -m "Add account keys endpoint for password change and recovery rotation"
```

### Task S4: Password reset takes wrapped keys and a blob decision

**Files:**
- Modify: `app/controllers/passwords_controller.rb`
- Modify: `test/integration/password_reset_security_test.rb`

- [ ] **Step 1: Rewrite the tests**

Replace the whole file:

```ruby
# test/integration/password_reset_security_test.rb
require "test_helper"

class PasswordResetSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:danny)
    @token = @user.password_reset_token
    @keys = { password: NEW_AUTH_HASH, password_wrapped_key: '{"nonce":"p","ciphertext":"q"}',
              recovery_wrapped_key: '{"nonce":"r","ciphertext":"s"}' }
  end

  test "edit renders the material the browser needs" do
    get edit_password_path(@token)

    assert_response :success
    assert_includes response.body, ERB::Util.html_escape(@user.recovery_wrapped_key),
      "the reset page must carry the recovery-wrapped key for the browser to unwrap"
  end

  test "blank password is rejected and leaves the password unchanged" do
    digest_before = @user.password_digest

    patch password_path(@token), params: @keys.merge(password: ""), as: :json

    assert_response :unprocessable_entity
    assert_equal digest_before, @user.reload.password_digest
    assert User.authenticate_by(email_address: @user.email_address, password: AUTH_HASH),
      "original password must still work since the reset did not happen"
  end

  test "missing password param is rejected rather than reported as success" do
    digest_before = @user.password_digest

    patch password_path(@token), params: @keys.except(:password), as: :json

    assert_response :unprocessable_entity
    assert_equal digest_before, @user.reload.password_digest
  end

  test "blank password does not destroy existing sessions" do
    @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

    patch password_path(@token), params: @keys.merge(password: ""), as: :json

    assert_equal 1, @user.sessions.count,
      "sessions must survive a reset that did not actually change the password"
  end

  test "recovery-code path swaps the password material, keeps the blob, revokes sessions, and signs in" do
    @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    @user.create_encrypted_blob!(ciphertext: "keep", nonce: "n")

    patch password_path(@token), params: @keys, as: :json

    assert_response :success
    assert_equal @user.id, response.parsed_body["account"]
    @user.reload
    assert User.authenticate_by(email_address: @user.email_address, password: NEW_AUTH_HASH)
    assert_equal '{"nonce":"p","ciphertext":"q"}', @user.password_wrapped_key
    assert_equal '{"nonce":"r","ciphertext":"s"}', @user.recovery_wrapped_key
    assert_equal "keep", @user.encrypted_blob.ciphertext
    assert_equal 1, @user.sessions.count, "old sessions revoked, the reset's own session started"

    get screen_path("journal")
    assert_response :success
  end

  test "device path replaces the blob" do
    @user.create_encrypted_blob!(ciphertext: "old", nonce: "n")

    patch password_path(@token), params: @keys.merge(blob: { ciphertext: "rekeyed", nonce: "n2" }), as: :json

    assert_response :success
    assert_equal "rekeyed", @user.reload.encrypted_blob.ciphertext
  end

  test "device path creates the blob when none exists" do
    patch password_path(@token), params: @keys.merge(blob: { ciphertext: "first", nonce: "n1" }), as: :json

    assert_response :success
    assert_equal "first", @user.reload.encrypted_blob.ciphertext
  end

  test "wipe path destroys the blob" do
    @user.create_encrypted_blob!(ciphertext: "old", nonce: "n")

    patch password_path(@token), params: @keys.merge(wipe: true), as: :json

    assert_response :success
    assert_nil @user.reload.encrypted_blob
  end

  test "an invalid blob rejects the whole reset" do
    @user.create_encrypted_blob!(ciphertext: "old", nonce: "n")
    digest_before = @user.password_digest

    patch password_path(@token), params: @keys.merge(blob: { ciphertext: "", nonce: "n2" }), as: :json

    assert_response :unprocessable_entity
    @user.reload
    assert_equal digest_before, @user.password_digest
    assert_equal "old", @user.encrypted_blob.ciphertext
  end

  test "blob and wipe together are rejected" do
    patch password_path(@token), params: @keys.merge(blob: { ciphertext: "x", nonce: "n" }, wipe: true), as: :json
    assert_response :unprocessable_entity
  end

  test "missing wrapped keys are rejected" do
    patch password_path(@token), params: { password: NEW_AUTH_HASH }, as: :json
    assert_response :unprocessable_entity
  end

  test "a raw password is rejected" do
    patch password_path(@token), params: @keys.merge(password: "correct horse battery"), as: :json
    assert_response :unprocessable_entity
    assert_match(/JavaScript/, response.parsed_body["errors"].join)
  end

  test "an expired or bogus token is rejected" do
    patch password_path("bogus"), params: @keys, as: :json
    assert_response :redirect
    assert_redirected_to new_password_path
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/integration/password_reset_security_test.rb`
Expected: most FAIL (current action redirects, ignores wrapped keys and blob).

- [ ] **Step 3: Implement**

```ruby
# app/controllers/passwords_controller.rb
class PasswordsController < ApplicationController
  allow_unauthenticated_access
  layout "session"
  # JSON bodies here are flat. Without this, a body missing `password` would be
  # wrapped under params[:password] by ParamsWrapper and pass the blank check.
  wrap_parameters false
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  # The view renders @user's recovery-wrapped key, id, and email as data
  # attributes: the browser needs them to unwrap with a recovery code, stamp
  # the device, and salt the new password.
  def edit
  end

  # Three client paths land here, all with a new auth hash and both wrapped
  # keys: recovery code (no blob change), device re-key (`blob` replaces),
  # or start over (`wipe` destroys). The server can't tell which key material
  # is "right"; it only enforces that the pieces arrive together.
  def update
    if params[:password].blank?
      return render json: { errors: [ "Password can't be blank." ] }, status: :unprocessable_entity
    end
    if params[:blob].present? && params[:wipe].present?
      return render json: { errors: [ "Choose either a new blob or a wipe, not both." ] }, status: :unprocessable_entity
    end

    User.transaction do
      @user.update!(params.permit(:password, :password_wrapped_key, :recovery_wrapped_key))
      if params[:blob].present?
        blob = @user.encrypted_blob || @user.build_encrypted_blob
        blob.update!(params.require(:blob).permit(:ciphertext, :nonce))
      elsif params[:wipe].present?
        @user.encrypted_blob&.destroy!
      end
      @user.sessions.destroy_all
    end

    start_new_session_for @user
    render json: { account: @user.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/integration/password_reset_security_test.rb`
Expected: PASS except `"edit renders the material the browser needs"`, which depends on Lane K's view. Mark that one `skip "view is written in Lane K"` for now with the skip as the first line of the test body; the driver removes the skip at integration.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/passwords_controller.rb test/integration/password_reset_security_test.rb
git commit -m "Password reset takes wrapped keys and decides the blob's fate"
```

### Task S5: Remove the passphrase reset endpoint, make salt optional, update lockdown test

**Files:**
- Modify: `app/controllers/api/sync_controller.rb`
- Modify: `config/routes.rb`
- Modify: `test/controllers/api/sync_controller_test.rb`
- Modify: `test/integration/authentication_lockdown_test.rb`

- [ ] **Step 1: Update the tests**

In `test/controllers/api/sync_controller_test.rb`: delete every test from the `# --- passphrase reset ---` comment through `"reset with an invalid blob is rejected without touching the old blob"`. Change every `create_encrypted_blob!(... salt: "s")` to drop the `salt:` argument. Replace `"show still returns the blob material"` with:

```ruby
  test "show returns the blob material" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "cipher", nonce: "nonce")
    sign_in_as user

    get api_sync_path, headers: { "Accept" => "application/json" }

    assert_equal "cipher", response.parsed_body["ciphertext"]
    assert_equal "nonce", response.parsed_body["nonce"]
  end

  test "update saves a blob without a salt" do
    user = users(:danny)
    sign_in_as user

    put api_sync_path, params: { blob: { ciphertext: "cipher", nonce: "nonce" } }, as: :json

    assert_response :success
    assert_equal "cipher", user.reload.encrypted_blob.ciphertext
    assert_nil user.encrypted_blob.salt
  end
```

In `test/integration/authentication_lockdown_test.rb`, replace the `"sync api requires authentication"` test with:

```ruby
  test "sync api requires authentication" do
    get api_sync_path, headers: { "Accept" => "application/json" }
    assert_response :unauthorized

    put api_sync_path, params: { blob: { ciphertext: "x", nonce: "n" } }, as: :json
    assert_response :unauthorized
  end

  test "account keys api requires authentication" do
    get api_account_keys_path, headers: { "Accept" => "application/json" }
    assert_response :unauthorized

    put api_account_keys_path, params: { current_password: AUTH_HASH, recovery_wrapped_key: WRAPPED_KEY }, as: :json
    assert_response :unauthorized
  end
```

- [ ] **Step 2: Run to verify the new update test fails**

Run: `bin/rails test test/controllers/api/sync_controller_test.rb`
Expected: `"update saves a blob without a salt"` passes already (salt is optional since F2); the file must load without `reset_api_sync_path` references. If any remain, the run errors: delete them.

- [ ] **Step 3: Remove the endpoint**

`config/routes.rb`: change the sync resource to

```ruby
    resource :sync, only: [ :show, :update ], controller: "sync"
```

`app/controllers/api/sync_controller.rb`: delete the second `rate_limit` block (the one for `:reset`), the `reset` action and its comment, and change `show` to no longer include `salt`:

```ruby
  def show
    blob = current_user.encrypted_blob
    if blob
      render json: {
        account: current_user.id,
        ciphertext: blob.ciphertext,
        nonce: blob.nonce,
        updated_at: blob.updated_at
      }
    else
      # Still name the account: the client stamps its local database with this
      # so it can tell whose data the device is holding.
      render json: { account: current_user.id }, status: :not_found
    end
  end
```

and `blob_params` to `params.require(:blob).permit(:ciphertext, :nonce)`.

- [ ] **Step 4: Run the whole suite**

Run: `bin/rails test && bin/rubocop`
Expected: `0 failures, 0 errors` (one skip from S4), rubocop clean.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/sync_controller.rb config/routes.rb test
git commit -m "Remove the passphrase reset endpoint and drop salt from sync"
```

### Task S6: Report done

Run `bin/rails test && bin/rubocop` one last time, then tell the driver Lane S
is complete and list the commits.

---

## Lane K — client auth (codex)

Only touch the files listed. Lane A imports from your `keys.js`, `request.js`,
and `db.js`, so keep the exported names exactly as the contract says. There is
no JavaScript test harness: after each task, load the file in the browser
console of the running dev server (`bin/dev`, then open the page) or at least
run `node --check <file>` on the module to catch syntax errors. Run
`bin/rails test` before each commit; nothing here should change the Ruby
results.

### Task K1: Key derivation and request libraries

**Files:**
- Create: `vendor/javascript/lib/keys.js`
- Create: `vendor/javascript/lib/request.js`
- Create: `test/integration/client_keys_contract_test.rb`

- [ ] **Step 1: Write the contract test**

```ruby
# test/integration/client_keys_contract_test.rb
require "test_helper"

# The one-secret model rests on properties of the browser code that no server
# test can observe. There is no JS harness, so pin them statically.
class ClientKeysContractTest < ActiveSupport::TestCase
  KEYS = Rails.root.join("vendor/javascript/lib/keys.js")
  AUTH_CONTROLLERS = %w[signup login password_reset].map do |name|
    Rails.root.join("app/javascript/controllers/#{name}_controller.js")
  end

  test "PBKDF2 uses at least 600000 rounds" do
    src = KEYS.read
    rounds = src[/PBKDF2_ROUNDS\s*=\s*(\d+)/, 1].to_i
    assert_operator rounds, :>=, 600_000
    assert_match(/iterations:\s*PBKDF2_ROUNDS/, src, "the stretch must use the exported constant")
  end

  test "the data key kept on the device is never extractable" do
    src = KEYS.read
    lock = src[/async function lockDataKey[^{]*\{(.+?)\n\}/m, 1]
    assert lock, "expected a lockDataKey function"
    assert_match(/importKey\("raw", raw, AES, false/, lock, "lockDataKey must import as non-extractable")
    assert_match(/extractable = false/, src, "unwrapDataKey must default to non-extractable")
  end

  test "auth controllers send the derived auth hash, never the password field" do
    AUTH_CONTROLLERS.each do |path|
      src = path.read
      assert_match(/password: authHash/, src, "#{path.basename} must send the auth hash as password")
      assert_no_match(/password:\s*(this\.)?password(Target)?(\.value)?\b(?!Hash)/, src,
        "#{path.basename} must never put the raw password in a request body")
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/integration/client_keys_contract_test.rb`
Expected: FAIL, `keys.js` missing (`Errno::ENOENT`).

- [ ] **Step 3: Write `keys.js`**

```js
// vendor/javascript/lib/keys.js
//
// Everything derived from the password happens here, in the browser. The
// server receives a one-way auth hash and wrapped copies of the data key. It
// never sees the password, the wrapping keys, or the data key itself.

export const MIN_PASSWORD_LENGTH = 12;
export const PBKDF2_ROUNDS = 600000;

const SALT_PREFIX = "client-key-v1:";
const RECOVERY_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; // Crockford base32
const RECOVERY_LENGTH = 20;
const AES = { name: "AES-GCM", length: 256 };

const encoder = new TextEncoder();
const subtle = window.crypto.subtle;

export function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

// Salting with the email avoids a pre-login round trip for a per-user salt.
// Emails can't change in this app, so the salt is stable.
async function saltFor(email) {
  const digest = await subtle.digest("SHA-256", encoder.encode(SALT_PREFIX + normalizeEmail(email)));
  return new Uint8Array(digest);
}

// Slow stretch of a secret into HKDF key material. About a second on a phone.
async function stretch(secret, salt) {
  const base = await subtle.importKey("raw", encoder.encode(secret), "PBKDF2", false, ["deriveBits"]);
  const bits = await subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations: PBKDF2_ROUNDS }, base, 256
  );
  return subtle.importKey("raw", bits, "HKDF", false, ["deriveKey", "deriveBits"]);
}

function hkdf(info) {
  return { name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: encoder.encode(info) };
}

function wrappingKeyFrom(material) {
  return subtle.deriveKey(hkdf("wrap"), material, AES, false, ["wrapKey", "unwrapKey"]);
}

// The wrapping key and the auth hash come from the same stretched material
// through HKDF with different labels, so knowing one says nothing about the
// other. Only the auth hash ever leaves the device.
export async function derivePasswordKeys(password, email) {
  const material = await stretch(password, await saltFor(email));
  const wrappingKey = await wrappingKeyFrom(material);
  const authBits = await subtle.deriveBits(hkdf("auth"), material, 256);
  return { wrappingKey, authHash: base64url(authBits) };
}

export async function deriveRecoveryWrappingKey(code, email) {
  const material = await stretch(normalizeRecoveryCode(code), await saltFor(email));
  return wrappingKeyFrom(material);
}

export function generateRecoveryCode() {
  // 256 divides evenly by 32, so a byte mod 32 is uniform.
  const bytes = window.crypto.getRandomValues(new Uint8Array(RECOVERY_LENGTH));
  const chars = Array.from(bytes, (b) => RECOVERY_ALPHABET[b % 32]).join("");
  return chars.match(/.{4}/g).join("-");
}

// Uppercase, strip separators, and fold the look-alikes Crockford excludes so
// a code read back off paper still matches.
export function normalizeRecoveryCode(input) {
  return input.toUpperCase().replace(/[^0-9A-Z]/g, "").replace(/O/g, "0").replace(/[IL]/g, "1");
}

// Extractable so it can be wrapped. Callers pass it through lockDataKey
// before storing it.
export function generateDataKey() {
  return subtle.generateKey(AES, true, ["encrypt", "decrypt"]);
}

export async function wrapDataKey(dataKey, wrappingKey) {
  const nonce = window.crypto.getRandomValues(new Uint8Array(12));
  const wrapped = await subtle.wrapKey("raw", dataKey, wrappingKey, { name: "AES-GCM", iv: nonce });
  return JSON.stringify({ nonce: base64(nonce), ciphertext: base64(wrapped) });
}

// Throws OperationError when the wrapping key is wrong. That is how a wrong
// password or recovery code is detected: nothing is verified server-side.
export async function unwrapDataKey(json, wrappingKey, { extractable = false } = {}) {
  const { nonce, ciphertext } = JSON.parse(json);
  return subtle.unwrapKey(
    "raw", fromBase64(ciphertext), wrappingKey,
    { name: "AES-GCM", iv: fromBase64(nonce) }, AES, extractable, ["encrypt", "decrypt"]
  );
}

// The copy that lives in IndexedDB and does the day-to-day decrypting can't
// be exported. Only the transient handles used for wrapping can.
export async function lockDataKey(extractableKey) {
  const raw = await subtle.exportKey("raw", extractableKey);
  return subtle.importKey("raw", raw, AES, false, ["encrypt", "decrypt"]);
}

function base64(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)));
}

function base64url(buffer) {
  return base64(buffer).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64(text) {
  return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
}
```

- [ ] **Step 4: Write `request.js`**

```js
// vendor/javascript/lib/request.js

// One JSON round trip. Never throws on HTTP errors: callers branch on
// `ok`/`status` and read `data.errors`. A non-JSON body (a redirect to an
// HTML page, say) yields `data = {}`.
export async function requestJSON(method, url, body) {
  const response = await fetch(url, {
    method,
    credentials: "same-origin",
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const data = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, data };
}
```

- [ ] **Step 5: Syntax check and run the contract test**

Run: `node --check vendor/javascript/lib/keys.js && node --check vendor/javascript/lib/request.js && bin/rails test test/integration/client_keys_contract_test.rb`
Expected: the first two contract tests PASS; the third still fails until K4–K6 exist. That is expected at this point.

- [ ] **Step 6: Commit**

```bash
git add vendor/javascript/lib/keys.js vendor/javascript/lib/request.js test/integration/client_keys_contract_test.rb
git commit -m "Add client key derivation and JSON request libraries"
```

### Task K2: Data key store in IndexedDB

**Files:**
- Modify: `vendor/javascript/lib/db.js`
- Modify: `vendor/javascript/lib/crypto.js`

- [ ] **Step 1: Bump the version and add the store**

Replace the top of the file down to `const ACCOUNT_STAMP = "account";` with:

```js
const DB_NAME = "crossroads_app";
const DB_VERSION = 3;

// "meta" and "keys" are bookkeeping, not user content: they are excluded from
// the synced state so they never travel to the server or get overwritten by
// an incoming blob. "keys" holds the non-extractable data key.
const STORE_KEY_PATHS = {
  profile: "id",
  journalEntries: "id",
  gratitudeEntries: "id",
  emotionSnapshots: "id",
  copingSkills: "text",
  triangleSnaps: "id",
  checkinEntries: "id",
  takeaways: "id",
  agendaItems: "id",
  settings: "id",
  meta: "id",
  keys: "id",
};

const LOCAL_ONLY_STORES = ["meta", "keys"];
const DATA_STORES = Object.keys(STORE_KEY_PATHS).filter((name) => !LOCAL_ONLY_STORES.includes(name));

const ACCOUNT_STAMP = "account";
const DATA_KEY = "dataKey";
```

Update the `onupgradeneeded` comment to: `// Create-if-missing so this covers a fresh install and upgrades from v1 (no "meta") and v2 (no "keys").`

- [ ] **Step 2: Add the accessors after `writeAccountStamp`**

```js
// The account's data key, stored as a non-extractable CryptoKey (IndexedDB
// structured-clones CryptoKey objects). Null on a device that has never
// signed in, or after logout wiped the database.
export async function readDataKey() {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const request = db.transaction("keys", "readonly").objectStore("keys").get(DATA_KEY);
    request.onsuccess = () => resolve(request.result ? request.result.key : null);
    request.onerror = () => reject(request.error);
  });
}

export async function writeDataKey(key) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction("keys", "readwrite");
    tx.objectStore("keys").put({ id: DATA_KEY, key });
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}
```

- [ ] **Step 3: Remove the passphrase derivation from `crypto.js`**

In `vendor/javascript/lib/crypto.js`, delete the whole `deriveKey` function
(from `export async function deriveKey(password, salt) {` through its closing
`}`) and the `const ENCODING = "base64";` line above it. `encrypt`, `decrypt`,
and the base64 helpers stay.

- [ ] **Step 4: Check and commit**

Run: `node --check vendor/javascript/lib/db.js && node --check vendor/javascript/lib/crypto.js && bin/rails test`
Expected: syntax OK; Ruby suite unchanged.

```bash
git add vendor/javascript/lib/db.js vendor/javascript/lib/crypto.js
git commit -m "Store the data key in IndexedDB and drop passphrase derivation"
```

### Task K3: Recovery code panel

**Files:**
- Create: `app/views/shared/_recovery_code.html.erb`
- Create: `app/javascript/controllers/recovery_code_controller.js`
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Write the partial**

```erb
<%# app/views/shared/_recovery_code.html.erb
    Shown once after a recovery code is made. The code exists only in the
    browser: whichever controller generated it dispatches recovery-code:show. %>
<div class="auth-screen" data-controller="recovery-code" hidden>
  <h2>Save your recovery code</h2>
  <p class="subtitle">If you forget your password, this code is the only way to get your entries back on a new phone. Save it somewhere safe.</p>
  <div class="card" data-controller="clipboard">
    <input type="text" readonly class="recovery-code" aria-label="Recovery code"
           data-clipboard-target="source" data-recovery-code-target="code">
    <button type="button" class="btn btn-o" style="width:100%;margin-top:8px;"
            data-clipboard-target="button" data-action="click->clipboard#copy">Copy code</button>
  </div>
  <div class="actions">
    <button type="button" class="btn" data-action="click->recovery-code#done">I've saved it</button>
  </div>
</div>
```

- [ ] **Step 2: Write the controller**

```js
// app/javascript/controllers/recovery_code_controller.js
import { Controller } from "@hotwired/stimulus";

// Reveals the "save your recovery code" panel. A controller that just made a
// code dispatches `recovery-code:show` with { code, next }. `next` is where
// "I've saved it" goes; null means just hide the panel again (settings).
export default class extends Controller {
  static targets = ["code"];

  connect() {
    this.handler = (event) => this.show(event.detail);
    document.addEventListener("recovery-code:show", this.handler);
  }

  disconnect() {
    document.removeEventListener("recovery-code:show", this.handler);
  }

  show({ code, next }) {
    this.next = next;
    this.codeTarget.value = code;
    this.element.hidden = false;
    this.element.scrollIntoView();
  }

  done() {
    this.codeTarget.value = "";
    if (this.next) {
      window.location.assign(this.next);
    } else {
      this.element.hidden = true;
    }
  }
}
```

- [ ] **Step 3: Add the style**

Append to `app/assets/stylesheets/application.css`:

```css
.recovery-code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:15px;letter-spacing:1px;text-align:center}
.auth-screen .show-password,.card .show-password{display:flex;align-items:center;gap:6px;font-weight:400;margin-top:6px;font-size:11px;color:var(--lt-brown)}
```

- [ ] **Step 4: Check and commit**

Run: `node --check app/javascript/controllers/recovery_code_controller.js`

```bash
git add app/views/shared/_recovery_code.html.erb app/javascript/controllers/recovery_code_controller.js app/assets/stylesheets/application.css
git commit -m "Add the recovery code panel"
```

### Task K4: Signup

**Files:**
- Modify: `app/views/users/new.html.erb`
- Create: `app/javascript/controllers/signup_controller.js`

- [ ] **Step 1: Rewrite the view**

```erb
<div class="auth-screen" data-controller="signup">
  <h2>Create Account</h2>
  <p class="subtitle">You'll need an invite code from your counselor.</p>

  <noscript><div class="form-error">This app needs JavaScript to keep your entries private. Please enable it and reload.</div></noscript>
  <div class="form-error" data-signup-target="error" hidden></div>
  <%= tag.div(flash[:alert], class: "form-error") if flash[:alert] %>

  <%= form_with model: @user, url: users_path, data: { action: "submit->signup#submit" } do |f| %>
    <div class="field">
      <%= f.label :email_address, "Email" %>
      <%= f.email_field :email_address, autofocus: true, autocomplete: "email", required: true,
            placeholder: "you@example.com", data: { signup_target: "email" } %>
    </div>

    <div class="field">
      <%= f.label :password %>
      <%= f.password_field :password, autocomplete: "new-password", required: true, minlength: 12,
            placeholder: "At least 12 characters", data: { signup_target: "password" } %>
      <label class="show-password"><input type="checkbox" data-action="change->signup#toggleVisibility"> Show password</label>
      <p class="field-hint">Your password also locks your entries. Nobody, including us, can read them or reset it for you.</p>
    </div>

    <div class="field">
      <%= f.label :invite_code, "Invite Code" %>
      <%= text_field_tag :"user[invite_code]", params[:code].presence, required: true,
            placeholder: "8-character code", data: { signup_target: "invite" } %>
    </div>

    <div class="actions">
      <%= f.submit "Sign Up", class: "btn", data: { signup_target: "submit" } %>
    </div>
  <% end %>

  <p class="auth-alt">
    Already have an account? <%= link_to "Sign in", new_session_path %>
    or <%= link_to "reset your password", new_password_path %>
  </p>
</div>
<%= render "shared/recovery_code" %>
```

- [ ] **Step 2: Write the controller**

```js
// app/javascript/controllers/signup_controller.js
import { Controller } from "@hotwired/stimulus";
import {
  MIN_PASSWORD_LENGTH, derivePasswordKeys, deriveRecoveryWrappingKey,
  generateRecoveryCode, generateDataKey, wrapDataKey, lockDataKey
} from "lib/keys";
import { requestJSON } from "lib/request";
import { clearData, writeDataKey, writeAccountStamp } from "lib/db";

export default class extends Controller {
  static targets = ["email", "password", "invite", "submit", "error"];

  toggleVisibility(event) {
    this.passwordTarget.type = event.target.checked ? "text" : "password";
  }

  async submit(event) {
    event.preventDefault();
    if (this.busy) return;

    const email = this.emailTarget.value;
    const password = this.passwordTarget.value;
    if (password.length < MIN_PASSWORD_LENGTH) {
      return this.fail(`Use a password of at least ${MIN_PASSWORD_LENGTH} characters.`);
    }

    this.start("Creating account…");
    try {
      const { wrappingKey, authHash } = await derivePasswordKeys(password, email);
      const recoveryCode = generateRecoveryCode();
      const recoveryKey = await deriveRecoveryWrappingKey(recoveryCode, email);
      const dataKey = await generateDataKey();

      const { ok, data } = await requestJSON("POST", "/users", { user: {
        email_address: email,
        password: authHash,
        invite_code: this.inviteTarget.value,
        password_wrapped_key: await wrapDataKey(dataKey, wrappingKey),
        recovery_wrapped_key: await wrapDataKey(dataKey, recoveryKey)
      } });
      if (!ok) return this.fail((data.errors || ["Sign up failed. Please try again."]).join(" "));

      // A brand-new account has nothing to merge: whatever this device held
      // belonged to someone else.
      await clearData();
      await writeDataKey(await lockDataKey(dataKey));
      await writeAccountStamp(data.account);

      this.element.hidden = true;
      document.dispatchEvent(new CustomEvent("recovery-code:show", { detail: { code: recoveryCode, next: "/" } }));
    } catch (e) {
      console.error("Signup failed:", e);
      this.fail("Sign up failed. Please try again.");
    } finally {
      this.stop();
    }
  }

  start(label) {
    this.busy = true;
    this.errorTarget.hidden = true;
    this.submitTarget.disabled = true;
    this.submitTarget.value = label;
  }

  stop() {
    this.busy = false;
    this.submitTarget.disabled = false;
    this.submitTarget.value = "Sign Up";
  }

  fail(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }
}
```

- [ ] **Step 3: Check and commit**

Run: `node --check app/javascript/controllers/signup_controller.js && bin/rails test test/controllers/users_controller_test.rb`
Expected: syntax OK; the two "signup form" HTML tests still pass.

```bash
git add app/views/users/new.html.erb app/javascript/controllers/signup_controller.js
git commit -m "Derive keys in the browser at signup"
```

### Task K5: Login

**Files:**
- Modify: `app/views/sessions/new.html.erb`
- Create: `app/javascript/controllers/login_controller.js`

- [ ] **Step 1: Rewrite the view**

```erb
<div class="auth-screen" data-controller="login">
  <h2>Welcome back</h2>
  <p class="subtitle">Sign in to reach your journal and check-ins.</p>

  <noscript><div class="form-error">This app needs JavaScript to keep your entries private. Please enable it and reload.</div></noscript>
  <% if params[:reason] == "changed" %>
    <div class="form-notice">Your password was changed on another device. Sign in again.</div>
  <% end %>
  <div class="form-error" data-login-target="error" hidden></div>
  <%= tag.div(flash[:alert], class: "form-error") if flash[:alert] %>
  <%= tag.div(flash[:notice], class: "form-notice") if flash[:notice] %>

  <%= form_with url: session_path, data: { action: "submit->login#submit" } do |form| %>
    <div class="field">
      <%= form.label :email_address, "Email" %>
      <%= form.email_field :email_address, required: true, autofocus: true,
            autocomplete: "username", placeholder: "you@example.com",
            value: params[:email_address], data: { login_target: "email" } %>
    </div>

    <div class="field">
      <%= form.label :password, "Password" %>
      <%= form.password_field :password, required: true,
            autocomplete: "current-password", placeholder: "Your password",
            data: { login_target: "password" } %>
    </div>

    <div class="actions">
      <%= form.submit "Sign in", class: "btn", data: { login_target: "submit" } %>
    </div>
  <% end %>

  <p class="auth-alt">
    <%= link_to "Forgot your password?", new_password_path %><br>
    Need an account? <%= link_to "Create one", new_user_path %>
  </p>
</div>
```

- [ ] **Step 2: Write the controller**

```js
// app/javascript/controllers/login_controller.js
import { Controller } from "@hotwired/stimulus";
import { derivePasswordKeys, unwrapDataKey } from "lib/keys";
import { requestJSON } from "lib/request";
import { readAccountStamp, clearData, writeDataKey, writeAccountStamp } from "lib/db";

export default class extends Controller {
  static targets = ["email", "password", "submit", "error"];

  async submit(event) {
    event.preventDefault();
    if (this.busy) return;

    this.start("Signing in…");
    try {
      const email = this.emailTarget.value;
      const { wrappingKey, authHash } = await derivePasswordKeys(this.passwordTarget.value, email);

      const { ok, status, data } = await requestJSON("POST", "/session", { email_address: email, password: authHash });
      if (status === 429) return this.fail("Too many attempts. Try again later.");
      if (!ok) return this.fail("Try another email address or password.");

      let dataKey;
      try {
        dataKey = await unwrapDataKey(data.password_wrapped_key, wrappingKey);
      } catch {
        // The auth hash matched but the wrapped key didn't: server-side
        // corruption. Don't leave a keyless session behind.
        await requestJSON("DELETE", "/session");
        return this.fail("Something is wrong with your account. Reset your password to continue.");
      }

      // A device that last held another account's entries must not merge
      // them into this one. Same account: keep them, boot merges the server
      // copy over the top.
      const stamp = await readAccountStamp();
      if (stamp !== null && stamp !== data.account) await clearData();
      await writeDataKey(dataKey);
      await writeAccountStamp(data.account);

      window.location.assign("/");
    } catch (e) {
      console.error("Login failed:", e);
      this.fail("Sign in failed. Check your connection and try again.");
    } finally {
      this.stop();
    }
  }

  start(label) {
    this.busy = true;
    this.errorTarget.hidden = true;
    this.submitTarget.disabled = true;
    this.submitTarget.value = label;
  }

  stop() {
    this.busy = false;
    this.submitTarget.disabled = false;
    this.submitTarget.value = "Sign in";
  }

  fail(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }
}
```

- [ ] **Step 3: Check and commit**

Run: `node --check app/javascript/controllers/login_controller.js && bin/rails test test/integration`

```bash
git add app/views/sessions/new.html.erb app/javascript/controllers/login_controller.js
git commit -m "Derive keys in the browser at login"
```

### Task K6: Password reset page

**Files:**
- Modify: `app/views/passwords/edit.html.erb`
- Create: `app/javascript/controllers/password_reset_controller.js`

- [ ] **Step 1: Rewrite the view**

```erb
<div class="auth-screen" data-controller="password-reset"
     data-password-reset-account-value="<%= @user.id %>"
     data-password-reset-email-value="<%= @user.email_address %>"
     data-password-reset-recovery-wrapped-key-value="<%= @user.recovery_wrapped_key %>"
     data-password-reset-token-value="<%= params[:token] %>">
  <h2>Set a new password</h2>
  <p class="subtitle">Choose a password of at least 12 characters.</p>

  <noscript><div class="form-error">This app needs JavaScript to keep your entries private. Please enable it and reload.</div></noscript>
  <div class="form-error" data-password-reset-target="error" hidden></div>
  <%= tag.div(flash[:alert], class: "form-error") if flash[:alert] %>

  <%= form_with url: password_path(params[:token]), method: :patch, data: { action: "submit->password-reset#submit" } do |form| %>
    <div class="field">
      <%= form.label :password, "New password" %>
      <%= form.password_field :password, required: true, minlength: 12,
            autocomplete: "new-password", placeholder: "At least 12 characters",
            data: { password_reset_target: "password" } %>
      <label class="show-password"><input type="checkbox" data-action="change->password-reset#toggleVisibility"> Show password</label>
    </div>

    <div class="field">
      <%= form.label :recovery_code, "Recovery code (if you have it)" %>
      <%= form.text_field :recovery_code, autocomplete: "off", autocapitalize: "characters", spellcheck: false,
            placeholder: "XXXX-XXXX-XXXX-XXXX-XXXX",
            data: { password_reset_target: "code", action: "input->password-reset#updateWarning" } %>
    </div>

    <p class="field-hint" data-password-reset-target="warning"></p>

    <div class="actions">
      <%= form.submit "Save password", class: "btn", data: { password_reset_target: "submit" } %>
    </div>
  <% end %>
</div>
<%= render "shared/recovery_code" %>
```

- [ ] **Step 2: Write the controller**

```js
// app/javascript/controllers/password_reset_controller.js
import { Controller } from "@hotwired/stimulus";
import {
  MIN_PASSWORD_LENGTH, derivePasswordKeys, deriveRecoveryWrappingKey,
  generateRecoveryCode, generateDataKey, wrapDataKey, unwrapDataKey, lockDataKey
} from "lib/keys";
import { encrypt } from "lib/crypto";
import { requestJSON } from "lib/request";
import { readAccountStamp, writeAccountStamp, writeDataKey, exportState, clearData } from "lib/db";

// Three outcomes, decided before submit and shown as a warning:
//   code   — the recovery code unwraps the data key; nothing is lost anywhere.
//   device — no code, but this device holds the account's entries: make a
//            new data key, re-encrypt what's here, replace the server blob.
//   wipe   — no code, nothing local: the backup is erased and they start over.
const WARNINGS = {
  code: "Your entries will be restored on this device.",
  device: "Your entries on this device will be kept. Entries made on other devices since this one last synced won't be included.",
  wipe: "Without your recovery code, your encrypted backup will be permanently erased and you will start fresh."
};

export default class extends Controller {
  static targets = ["password", "code", "warning", "submit", "error"];
  static values = { account: Number, email: String, recoveryWrappedKey: String, token: String };

  async connect() {
    const stamp = await readAccountStamp();
    this.deviceHoldsData = stamp !== null && stamp === this.accountValue;
    this.updateWarning();
  }

  path() {
    if (this.codeTarget.value.trim()) return "code";
    return this.deviceHoldsData ? "device" : "wipe";
  }

  updateWarning() {
    const path = this.path();
    this.warningTarget.textContent = WARNINGS[path];
    this.warningTarget.style.color = path === "wipe" ? "#c0392b" : "";
  }

  toggleVisibility(event) {
    this.passwordTarget.type = event.target.checked ? "text" : "password";
  }

  async submit(event) {
    event.preventDefault();
    if (this.busy) return;

    const newPassword = this.passwordTarget.value;
    if (newPassword.length < MIN_PASSWORD_LENGTH) {
      return this.fail(`Use a password of at least ${MIN_PASSWORD_LENGTH} characters.`);
    }
    const path = this.path();

    this.start("Saving…");
    try {
      const email = this.emailValue;
      const { wrappingKey, authHash } = await derivePasswordKeys(newPassword, email);
      const body = { password: authHash };
      let dataKey;
      let recoveryCode = null;

      if (path === "code") {
        const recoveryKey = await deriveRecoveryWrappingKey(this.codeTarget.value, email);
        try {
          dataKey = await unwrapDataKey(this.recoveryWrappedKeyValue, recoveryKey, { extractable: true });
        } catch {
          return this.fail("That recovery code doesn't match.");
        }
        body.recovery_wrapped_key = this.recoveryWrappedKeyValue;
      } else {
        dataKey = await generateDataKey();
        recoveryCode = generateRecoveryCode();
        const recoveryKey = await deriveRecoveryWrappingKey(recoveryCode, email);
        body.recovery_wrapped_key = await wrapDataKey(dataKey, recoveryKey);
        if (path === "device") {
          // Only ciphertext leaves the device, same as every save.
          const { ciphertext, nonce } = await encrypt(await exportState(), dataKey);
          body.blob = { ciphertext, nonce };
        } else {
          body.wipe = true;
        }
      }
      body.password_wrapped_key = await wrapDataKey(dataKey, wrappingKey);

      const { ok, data } = await requestJSON("PATCH", `/passwords/${encodeURIComponent(this.tokenValue)}`, body);
      if (!ok) return this.fail((data.errors || ["Reset failed. Please try again."]).join(" "));
      // An expired token redirects to an HTML page: fetch follows it, so
      // `ok` is true but there is no account in the body.
      if (data.account === undefined) return this.fail("This reset link is invalid or has expired. Request a new one.");

      // Keep local entries only on the device path, or the code path on the
      // device that already holds this account. Anything else is stale or
      // another account's.
      if (path === "wipe" || !this.deviceHoldsData) await clearData();
      await writeDataKey(await lockDataKey(dataKey));
      await writeAccountStamp(data.account);

      if (recoveryCode) {
        this.element.hidden = true;
        document.dispatchEvent(new CustomEvent("recovery-code:show", { detail: { code: recoveryCode, next: "/" } }));
      } else {
        window.location.assign("/");
      }
    } catch (e) {
      console.error("Password reset failed:", e);
      this.fail("Reset failed. Check your connection and try again.");
    } finally {
      this.stop();
    }
  }

  start(label) {
    this.busy = true;
    this.errorTarget.hidden = true;
    this.submitTarget.disabled = true;
    this.submitTarget.value = label;
  }

  stop() {
    this.busy = false;
    this.submitTarget.disabled = false;
    this.submitTarget.value = "Save password";
  }

  fail(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }
}
```

- [ ] **Step 3: Check, run the contract test, commit**

Run: `node --check app/javascript/controllers/password_reset_controller.js && bin/rails test test/integration/client_keys_contract_test.rb`
Expected: all three contract tests PASS now that the three controllers exist.

```bash
git add app/views/passwords/edit.html.erb app/javascript/controllers/password_reset_controller.js
git commit -m "Reset password with a recovery code, a device re-key, or a wipe"
```

### Task K7: Report done

Run `bin/rails test && bin/rubocop` one last time, then tell the driver Lane K is complete and list the commits.

---

## Lane A — app shell (grok)

Only touch the files listed. You import `readDataKey`, `writeDataKey` from
`lib/db`, `requestJSON` from `lib/request`, and several functions from
`lib/keys`. Lane K is writing those in the same checkout; the exact
signatures are in the Contract section at the top. If a file you import from
doesn't exist yet, keep going: your tests are static and don't execute the
imports. Run `node --check` on each JS file and `bin/rails test` before every
commit.

### Task A1: Shared device wipe and sign-out

**Files:**
- Create: `vendor/javascript/lib/session.js`
- Modify: `app/javascript/controllers/logout_controller.js`

- [ ] **Step 1: Write `session.js`**

```js
// vendor/javascript/lib/session.js
import { wipeAll } from "lib/db";
import { requestJSON } from "lib/request";

// Everything that makes a device forget an account: IndexedDB (entries and
// the data key) and the service worker caches. The server session is
// separate; see signOut.
export async function wipeDevice() {
  try {
    await Promise.all([wipeAll(), clearServiceWorkerCaches()]);
  } catch (e) {
    console.error("Device wipe failed:", e);
  }
}

// Wipe, end the server session, land on the login page. `reason` is a short
// token the login page turns into a message (only "changed" exists today).
export async function signOut({ reason } = {}) {
  await wipeDevice();
  await requestJSON("DELETE", "/session").catch(() => {});
  const url = reason ? `/session/new?reason=${encodeURIComponent(reason)}` : "/session/new";
  window.location.replace(url);
}

function clearServiceWorkerCaches() {
  return new Promise((resolve) => {
    const worker = navigator.serviceWorker?.controller;
    if (!worker) return resolve();
    const channel = new MessageChannel();
    const timer = setTimeout(resolve, 1000);
    channel.port1.onmessage = () => {
      clearTimeout(timer);
      resolve();
    };
    worker.postMessage({ type: "logout" }, [channel.port2]);
  });
}
```

- [ ] **Step 2: Use it from the logout controller**

In `app/javascript/controllers/logout_controller.js`:
- Replace `import { wipeAll } from "lib/db";` with `import { wipeDevice } from "lib/session";`.
- Replace the block

```js
    try {
      await Promise.all([wipeAll(), this.clearServiceWorkerCaches()]);
    } catch (e) {
      console.error("Logout cleanup failed:", e);
    }
    this.element.submit();
```

with

```js
    await wipeDevice();
    this.element.submit();
```

- Delete the whole `clearServiceWorkerCaches()` method at the bottom of the class.

- [ ] **Step 3: Check and commit**

Run: `node --check vendor/javascript/lib/session.js && node --check app/javascript/controllers/logout_controller.js && bin/rails test test/integration/service_worker_contract_test.rb`
Expected: syntax OK; the service worker contract test still passes (it pins `public/service-worker.js`, which is unchanged).

```bash
git add vendor/javascript/lib/session.js app/javascript/controllers/logout_controller.js
git commit -m "Share device wipe and sign-out between logout and boot"
```

### Task A2: Boot from the stored data key; remove the unlock overlay

**Files:**
- Modify: `app/javascript/controllers/sync_controller.js`
- Modify: `app/views/layouts/application.html.erb`
- Delete: `test/integration/client_unlock_contract_test.rb`
- Delete: `test/integration/client_reset_contract_test.rb`
- Create: `test/integration/client_boot_contract_test.rb`

- [ ] **Step 1: Write the new contract test and delete the old ones**

```bash
git rm test/integration/client_unlock_contract_test.rb test/integration/client_reset_contract_test.rb
```

```ruby
# test/integration/client_boot_contract_test.rb
require "test_helper"

# Boot decides between "unlocked" and "signed out" on every page load. There
# is no JS harness, so pin the decisions statically.
class ClientBootContractTest < ActiveSupport::TestCase
  SYNC = Rails.root.join("app/javascript/controllers/sync_controller.js")
  LAYOUT = Rails.root.join("app/views/layouts/application.html.erb")

  def boot_body
    SYNC.read[/async boot\s*\(\)\s*\{(.+?)\n  \}/m, 1]
  end

  test "a device without a data key is signed out" do
    assert_match(/if \(!this\.key\) return signOut\(\)/, boot_body)
  end

  test "a blob that will not decrypt signs out with the changed reason and never uploads first" do
    body = boot_body
    assert_match(/signOut\(\{ reason: "changed" \}\)/, body)
    assert_no_match(/this\.save\(\)/, body, "boot must not upload local state before deciding")
  end

  test "a network failure still unlocks with local data" do
    rescue_block = boot_body[/catch \(e\) \{(.+?)\n    \}/m, 1]
    assert rescue_block, "expected a catch block in boot"
    assert_match(/this\.markUnlocked\(\)/, rescue_block)
  end

  test "save uploads only ciphertext and nonce" do
    save = SYNC.read[/async save\(\)\s*\{(.+?)\n  \}/m, 1]
    assert_match(/blob: \{ ciphertext, nonce \}/, save)
    assert_no_match(/salt/, save)
  end

  test "the passphrase overlay is gone" do
    assert_no_match(/unlock-overlay|passphrase/i, LAYOUT.read)
    assert_no_match(/passphrase|deriveKey/i, SYNC.read)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/integration/client_boot_contract_test.rb`
Expected: FAIL on every test (no `boot` method yet, overlay still present).

- [ ] **Step 3: Rewrite `sync_controller.js`**

```js
// app/javascript/controllers/sync_controller.js
import { Controller } from "@hotwired/stimulus";
import { encrypt, decrypt } from "lib/crypto";
import { readDataKey, exportState, mergeState, writeAccountStamp } from "lib/db";
import { signOut } from "lib/session";

export default class extends Controller {
  connect() {
    this.key = null;
    this.unlocked = false;
    this.saveHandler = () => this.save();
    // Logout flushes through this handshake before wiping the device, so a
    // failed upload can block the wipe instead of destroying unsynced data.
    this.flushHandler = async () => {
      const ok = await this.save();
      document.dispatchEvent(new CustomEvent("sync:flushed", { detail: { ok } }));
    };
    // A bfcache restore would revive the unlocked DOM (decrypted entries)
    // after logout. Force a clean boot instead.
    this.pageshowHandler = (event) => {
      if (event.persisted) window.location.reload();
    };
    // iOS Safari pans the whole page up to keep a focused input above the
    // keyboard and sometimes never pans back after the keyboard closes,
    // leaving the page stuck half off-screen. Once the visual viewport is
    // back to full height, snap the scroll position home.
    this.viewportHandler = () => {
      const vv = window.visualViewport;
      if (vv.height >= window.innerHeight - 1 && (window.scrollY > 0 || vv.offsetTop > 0)) {
        window.scrollTo(0, 0);
      }
    };
    document.addEventListener("sync:save", this.saveHandler);
    document.addEventListener("sync:flush", this.flushHandler);
    window.addEventListener("pageshow", this.pageshowHandler);
    window.visualViewport?.addEventListener("resize", this.viewportHandler);
    this.boot();
  }

  disconnect() {
    document.removeEventListener("sync:save", this.saveHandler);
    document.removeEventListener("sync:flush", this.flushHandler);
    window.removeEventListener("pageshow", this.pageshowHandler);
    window.visualViewport?.removeEventListener("resize", this.viewportHandler);
  }

  // Login is the only gate: the device either holds the data key or it
  // doesn't. The server copy only decides what to merge; losing the network
  // must not lock a user out of entries that are already on the device.
  async boot() {
    try {
      this.key = await readDataKey();
      if (!this.key) return signOut();

      const response = await fetch("/api/sync", {
        headers: { "Accept": "application/json" },
        credentials: "same-origin",
        cache: "no-store"
      });
      if (response.status === 401) return signOut();
      if (response.status === 404) {
        // Fresh account: nothing to import yet.
        const { account } = await response.json().catch(() => ({}));
        if (account !== undefined) await writeAccountStamp(account);
        return this.markUnlocked();
      }
      if (!response.ok) return this.markUnlocked();

      const blob = await response.json();
      let plaintext;
      try {
        plaintext = await decrypt(blob.ciphertext, blob.nonce, this.key);
      } catch {
        // The blob was re-keyed by a password reset on another device. This
        // device's key is dead, and nothing here is uploaded first, so the
        // newer blob survives.
        return signOut({ reason: "changed" });
      }
      await mergeState(plaintext);
      await writeAccountStamp(blob.account);
      this.markUnlocked();
    } catch (e) {
      console.error("Sync load failed, using local data:", e);
      this.markUnlocked();
    }
  }

  markUnlocked() {
    this.unlocked = true;
    document.dispatchEvent(new CustomEvent("app:unlocked", { bubbles: true }));
  }

  async save() {
    // Locked means the screens never rendered, so nothing new was written.
    if (!this.key || !this.unlocked) return true;

    // Abort rather than hang so every caller gets a settled answer, and no
    // upload is left in flight for a later logout navigation to kill.
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), 10000);
    try {
      const state = await exportState();
      const { ciphertext, nonce } = await encrypt(state, this.key);

      const response = await fetch("/api/sync", {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        credentials: "same-origin",
        signal: abort.signal,
        body: JSON.stringify({ blob: { ciphertext, nonce } })
      });

      // A rejected save means this entry exists only on this device. Say so
      // rather than letting the backup silently fall behind.
      if (!response.ok) this.warnSaveFailed(response.status);
      return response.ok;
    } catch (error) {
      this.warnSaveFailed(error);
      return false;
    } finally {
      clearTimeout(timer);
    }
  }

  warnSaveFailed(reason) {
    console.error("Sync save failed:", reason);
    const el = document.getElementById("flash-container");
    if (!el) return;
    el.innerHTML = '<div class="flash">Saved on this device, but not backed up. Check your connection.</div>';
    setTimeout(() => { el.innerHTML = ""; }, 4000);
  }

  clear() {
    this.key = null;
    this.unlocked = false;
  }
}
```

- [ ] **Step 4: Remove the overlay from the layout**

In `app/views/layouts/application.html.erb`, delete everything from the line
`<% if authenticated? %>` (just after `<div id="flash-container"></div>`)
through the matching `<% end %>` that precedes `<div class="content" id="main-content">`.
That block is the `<!-- Passphrase unlock overlay -->` comment and the
`#unlock-overlay` div. Nothing else in the layout changes.

- [ ] **Step 5: Run the tests**

Run: `node --check app/javascript/controllers/sync_controller.js && bin/rails test`
Expected: `client_boot_contract_test` PASS; whole suite green.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/sync_controller.js app/views/layouts/application.html.erb test/integration/client_boot_contract_test.rb
git commit -m "Boot from the stored data key and drop the passphrase overlay"
```

### Task A3: Change password and new recovery code in Settings

**Files:**
- Modify: `app/views/screens/settings.html.erb`
- Create: `app/javascript/controllers/account_controller.js`

- [ ] **Step 1: Add the cards to the settings screen**

Insert before the `<div class="card">` that holds the Log Out button:

```erb
  <div class="card" data-controller="account" data-account-email-value="<%= current_user.email_address %>">
    <label class="lbl">Change password</label>
    <input type="password" placeholder="Current password" autocomplete="current-password"
           data-account-target="currentPassword" />
    <input type="password" placeholder="New password (at least 12 characters)" autocomplete="new-password"
           style="margin-top:8px;" data-account-target="newPassword" />
    <button class="btn" style="margin-top:10px;" data-account-target="changeButton"
            data-action="click->account#changePassword">Change Password</button>

    <label class="lbl" style="margin-top:18px;">Recovery code</label>
    <p class="subtitle">Lost it? Make a new one. The old code stops working.</p>
    <input type="password" placeholder="Current password" autocomplete="current-password"
           data-account-target="rotatePassword" />
    <button class="btn btn-o" style="margin-top:10px;" data-account-target="rotateButton"
            data-action="click->account#rotateRecoveryCode">New Recovery Code</button>

    <p class="form-error" style="margin-top:10px;" data-account-target="error" hidden></p>
  </div>
  <%= render "shared/recovery_code" %>
```

- [ ] **Step 2: Write the controller**

```js
// app/javascript/controllers/account_controller.js
import { Controller } from "@hotwired/stimulus";
import {
  MIN_PASSWORD_LENGTH, derivePasswordKeys, deriveRecoveryWrappingKey,
  generateRecoveryCode, wrapDataKey, unwrapDataKey
} from "lib/keys";
import { requestJSON } from "lib/request";

// Both actions re-wrap the data key, which needs an extractable handle, and
// the local copy is deliberately not extractable. So: fetch the
// password-wrapped copy, unwrap it with the current password (which also
// checks the password locally), re-wrap, send. The server verifies the
// current auth hash again before saving anything.
export default class extends Controller {
  static targets = ["currentPassword", "newPassword", "changeButton", "rotatePassword", "rotateButton", "error"];
  static values = { email: String };

  async changePassword() {
    const current = this.currentPasswordTarget.value;
    const next = this.newPasswordTarget.value;
    if (next.length < MIN_PASSWORD_LENGTH) {
      return this.showError(`Use a password of at least ${MIN_PASSWORD_LENGTH} characters.`);
    }

    await this.run(this.changeButtonTarget, async () => {
      const { dataKey, authHash } = await this.unlockWithPassword(current);
      const { wrappingKey, authHash: newAuthHash } = await derivePasswordKeys(next, this.emailValue);
      const { ok, data } = await requestJSON("PUT", "/api/account/keys", {
        current_password: authHash,
        password: newAuthHash,
        password_wrapped_key: await wrapDataKey(dataKey, wrappingKey)
      });
      if (!ok) throw new Error((data.errors || ["Could not change the password."]).join(" "));

      this.currentPasswordTarget.value = "";
      this.newPasswordTarget.value = "";
      this.flash("Password changed.");
    });
  }

  async rotateRecoveryCode() {
    await this.run(this.rotateButtonTarget, async () => {
      const { dataKey, authHash } = await this.unlockWithPassword(this.rotatePasswordTarget.value);
      const code = generateRecoveryCode();
      const recoveryKey = await deriveRecoveryWrappingKey(code, this.emailValue);
      const { ok, data } = await requestJSON("PUT", "/api/account/keys", {
        current_password: authHash,
        recovery_wrapped_key: await wrapDataKey(dataKey, recoveryKey)
      });
      if (!ok) throw new Error((data.errors || ["Could not make a new recovery code."]).join(" "));

      this.rotatePasswordTarget.value = "";
      document.dispatchEvent(new CustomEvent("recovery-code:show", { detail: { code, next: null } }));
    });
  }

  async unlockWithPassword(password) {
    const { wrappingKey, authHash } = await derivePasswordKeys(password, this.emailValue);
    const { ok, data } = await requestJSON("GET", "/api/account/keys");
    if (!ok) throw new Error("Couldn't reach the server. Check your connection.");
    try {
      const dataKey = await unwrapDataKey(data.password_wrapped_key, wrappingKey, { extractable: true });
      return { dataKey, authHash };
    } catch {
      throw new Error("Incorrect current password.");
    }
  }

  async run(button, work) {
    if (this.busy) return;
    this.busy = true;
    button.disabled = true;
    this.errorTarget.hidden = true;
    try {
      await work();
    } catch (e) {
      this.showError(e.message);
    } finally {
      this.busy = false;
      button.disabled = false;
    }
  }

  showError(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }

  flash(text) {
    const el = document.getElementById("flash-container");
    if (!el) return;
    el.innerHTML = `<div class="flash">${text}</div>`;
    setTimeout(() => { el.innerHTML = ""; }, 2200);
  }
}
```

- [ ] **Step 3: Check and commit**

Run: `node --check app/javascript/controllers/account_controller.js && bin/rails test`
Expected: syntax OK; `authentication_lockdown_test` still renders every screen for a signed-in user, including settings, so `current_user.email_address` must resolve.

```bash
git add app/views/screens/settings.html.erb app/javascript/controllers/account_controller.js
git commit -m "Change password and rotate the recovery code from Settings"
```

### Task A4: Report done

Run `bin/rails test && bin/rubocop`, then tell the driver Lane A is complete and list the commits.

---

## Integration (driver)

- [ ] **Step 1: Wait for all three lanes**, then `git log --oneline` to confirm every lane's commits are on `product-ready` and `git status` is clean.

- [ ] **Step 2: Remove the skip** in `test/integration/password_reset_security_test.rb` (`"edit renders the material the browser needs"`) and confirm it passes against Lane K's view.

- [ ] **Step 3: Grep for leftovers**

Run: `grep -rni 'passphrase' app vendor public test --include='*.rb' --include='*.erb' --include='*.js' ; grep -rn 'MINIMUM_PASSWORD_LENGTH\|reset_api_sync\|password_confirmation' app test config`
Expected: no output.

- [ ] **Step 4: Full CI**

Run: `bin/ci`
Expected: every step green, including rubocop, bundler-audit, importmap audit, brakeman. Fix anything red before the browser pass.

- [ ] **Step 5: Browser checklist** (Safari on iOS and Chrome on desktop, against `bin/dev`; the driver's Chrome tools cover the desktop half). Generate an invite code from `/admin/invites` first.

1. Sign up, save the recovery code, add a journal entry, reload: still unlocked, entry present.
2. Log out, log in on a second browser: entry present.
3. Forgot password with the recovery code on a third browser: entry present, no recovery screen.
4. Forgot password without the code on the first browser: warning says entries on this device are kept; after reset the entry is present and a new code is shown. Then reload the second browser: it lands on login with the "changed on another device" message.
5. Forgot password without the code on a fresh browser: wipe warning shown; after reset the app is empty.
6. Settings: change password, log out, log in with the new password. Settings: new recovery code shows a code; "I've saved it" hides the panel.
7. Wrong password at login shows the inline error and the button re-enables.
8. Signup with JavaScript disabled shows the "requires JavaScript" error and creates no user.

- [ ] **Step 6: Push and open the PR to `main`**

```bash
git push -u origin product-ready
gh pr create --base main --title "One-secret login with recovery codes" --body-file docs/superpowers/specs/2026-09-16-one-secret-login-design.md
```

- [ ] **Step 7: Before deploying**, tell the user in plain words that the launch migration deletes every client account, blob, session, and invite code in production, and get an explicit go-ahead.
