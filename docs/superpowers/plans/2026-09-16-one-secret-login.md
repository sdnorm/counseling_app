# One-Secret Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the password-plus-passphrase login with a single password from which the browser derives an auth hash and a key-wrapping key, plus a recovery code, without the server ever seeing a password or a data key.

**Architecture:** A random data key encrypts the journal blob. The browser wraps that key twice (under a password-derived key and a recovery-code-derived key) and the server stores only the wrapped copies plus a bcrypt of a one-way auth hash. Login, signup, reset, and settings are Stimulus controllers that do the derivation and talk JSON to Rails; app boot reads the data key from IndexedDB and decrypts.

**Tech Stack:** Rails 8.1, SQLite, `has_secure_password`, Stimulus via importmap, Web Crypto API (PBKDF2, HKDF, AES-GCM, wrapKey/unwrapKey), IndexedDB, Minitest.

**Spec:** `docs/superpowers/specs/2026-09-16-one-secret-login-design.md`

---

## How this plan is executed

Work is split into lanes. Each lane is a Herdr worktree with its own branch
and its own agent. Lanes never edit the same file. The driver (Claude in the
`product-ready` worktree) does the Foundation first, then spawns the lanes,
then integrates.

| Lane | Agent | Branch | Owns |
|---|---|---|---|
| Foundation | driver | `product-ready` | migrations, `app/models/user.rb`, `app/models/encrypted_blob.rb`, `test/fixtures/users.yml`, `test/test_helper.rb`, mechanical updates to existing tests |
| S — server | pi | `login-server` | `app/controllers/**`, `config/routes.rb`, `test/controllers/**`, `test/integration/authentication_lockdown_test.rb`, `test/integration/password_reset_security_test.rb` |
| K — client auth | claude | `login-client-auth` | `vendor/javascript/lib/keys.js`, `vendor/javascript/lib/request.js`, `vendor/javascript/lib/db.js`, `app/javascript/controllers/{signup,login,password_reset,recovery_code}_controller.js`, `app/views/{sessions,users,passwords}/**`, `app/views/shared/_recovery_code.html.erb`, `app/views/layouts/session.html.erb` |
| A — app shell | grok | `login-app` | `app/javascript/controllers/{sync,logout,account}_controller.js`, `vendor/javascript/lib/session.js`, `app/views/layouts/application.html.erb`, `app/views/screens/settings.html.erb`, `test/integration/client_*_contract_test.rb` |

Lane branches are cut from `product-ready` after the Foundation commit.
Each lane commits after every task, pushes its branch, and opens a PR
against `product-ready`. The driver squash-merges in the order K, S, A,
then runs the browser checklist in the Integration section.

Lanes K and A both call functions defined in Lane K. Lane A codes against the
contract below without waiting; the driver merges K before A.

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

## Lane S — server (pi, branch `login-server`)

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
  rate_limit to: 10, within: 3.minutes, only: :create, with: :too_many_attempts

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
  rate_limit to: 10, within: 10.minutes, only: :create, with: :too_many_attempts

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
    assert_includes response.body, @user.recovery_wrapped_key
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

### Task S6: Push and open the PR

- [ ] **Step 1: Push**

Run: `git push -u origin login-server`

- [ ] **Step 2: Open the PR against `product-ready`**

```bash
gh pr create --base product-ready --title "One-secret login: server" --body "Lane S of docs/superpowers/plans/2026-09-16-one-secret-login.md. JSON login/signup, account keys endpoint, wrapped-key password reset, passphrase reset endpoint removed."
```

Report the PR URL back to the driver.
