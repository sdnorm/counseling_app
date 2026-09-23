# One-Secret Login

**Date:** 2026-09-16
**Status:** Approved
**Part of:** `2026-09-16-pivot-roadmap.md`, project 1

## Problem

Clients have two secrets: an account password that authenticates to the
server, and a data passphrase that derives the encryption key in the
browser. Users report being confused by the sign-in process, and the
passphrase is the likely cause: two prompts on every load, two things to
forget, and copy that has to explain why they are different.

The zero-knowledge model (server holds only ciphertext) must survive.

## Decision

One password. The browser derives everything from it before anything
touches the network. The server sees only a one-way auth hash and wrapped
keys it cannot open. A recovery code, shown once at signup, lets a client
recover their data on a new device after forgetting their password.

There is no migration path for existing accounts. The launch migration
clears client accounts, sessions, blobs, push subscriptions, and invite
codes. The counselor re-invites clients.

## Key model

All keys are made with the Web Crypto API in the browser.

| Key | How it is made | Where it lives |
|---|---|---|
| **Data key** | `AES-GCM` 256-bit, random, generated once at signup | Device only, as a non-extractable key in IndexedDB. Server holds two wrapped copies. |
| **Password key** | `PBKDF2-SHA256(password, salt, 600000 rounds)` → 32 bytes | Transient, in memory during login, signup, password change, and reset |
| **Recovery key** | `PBKDF2-SHA256(recovery code, salt, 600000 rounds)` → 32 bytes | Transient, in memory during signup, rotation, and reset |

Where `salt = SHA-256("client-key-v1:" + normalized email)`. The email is
lowercased and stripped, matching the server's normalization. Salting with
the email avoids a pre-login round trip; emails are not changeable in this
app.

From the password key, two values are derived with `HKDF-SHA256` (empty
salt, 256 bits each):

- `info = "wrap"` → the **password wrapping key** (`AES-GCM`, wraps the data
  key).
- `info = "auth"` → the **auth hash**, base64url without padding, 43
  characters. This is what the server receives as the `password` parameter
  and stores with the existing `has_secure_password` bcrypt path.

From the recovery key, `HKDF-SHA256(info = "wrap")` → the **recovery
wrapping key**.

**Wrapped key format.** `AES-GCM` with a random 12-byte nonce. Stored and
transmitted as a JSON string: `{"nonce": "<base64>", "ciphertext": "<base64>"}`.
Maximum 256 bytes.

**Recovery code format.** 20 characters from the Crockford base32 alphabet
(no I, L, O, U), displayed in five groups of four separated by dashes,
e.g. `K3H7-9XQ2-M4PD-7TWA-2CBF`. About 100 bits of entropy. Input is
normalized by uppercasing and removing dashes and spaces. The code itself is
never stored anywhere.

**Data key handling.** The data key is generated extractable so it can be
wrapped, then the raw bytes are imported as a non-extractable key for local
storage and use, and the extractable handle is dropped. `unwrapKey` at login
produces a non-extractable key directly. Raw key bytes exist in memory only
during signup, rotation, and reset.

**Password rules.** Minimum 12 characters, enforced client-side (the server
never sees the password). No confirmation field; a show/hide toggle instead.

## Data model

Migration on `users`:

- `password_wrapped_key`, text, not null.
- `recovery_wrapped_key`, text, not null.

`encrypted_blobs.salt` becomes nullable and is no longer read or written by
the client. `nonce` and `ciphertext` are unchanged.

The launch migration deletes all rows from `sessions`, `push_subscriptions`,
`encrypted_blobs`, `users`, and `invite_codes` before adding the not-null
columns.

`User` changes:

- The minimum-length validation on `password` is replaced by a format
  validation: `/\A[A-Za-z0-9_-]{43}\z/` with the message "requires
  JavaScript to be enabled". A raw password submitted at signup by a client
  whose JavaScript failed is rejected rather than stored. At login a raw
  password simply fails to authenticate. Both pages carry a `<noscript>`
  notice saying the app needs JavaScript.
- `validates :password_wrapped_key, :recovery_wrapped_key, presence: true,
  length: { maximum: 256 }`.
- `MINIMUM_PASSWORD_LENGTH` is removed from the model; the client owns it.

## Server surface

| Route | Change |
|---|---|
| `POST /session` | `password` is the auth hash. Responds to JSON: on success `200 { account, password_wrapped_key }` (`account` is the user id the client stamps its database with), on failure `401 { errors }`. HTML form fallback keeps redirecting as today. |
| `POST /users` | Accepts `email_address`, `password` (auth hash), `invite_code`, `password_wrapped_key`, `recovery_wrapped_key`. Responds to JSON: `201 { account }` or `422 { errors }`. Starts a session. |
| `GET /api/account/keys` | New. Returns both wrapped keys. The settings flows unwrap the password-wrapped copy with the current password to get a re-wrappable handle, since the device's own copy is non-extractable. |
| `PUT /api/account/keys` | New. Body: `current_password` (auth hash, required), plus any of `password` (new auth hash), `password_wrapped_key`, `recovery_wrapped_key`. Verifies `current_password` with `authenticate`, then updates the given fields in one transaction. When `password` changes, every other session for the user is destroyed. Rate limited like login (10 per 3 minutes, keyed by user). Wrong current password → 401 JSON. |
| `GET /passwords/:token/edit` | Renders `recovery_wrapped_key` and the account id into the page as data attributes for the client reset flow. |
| `PATCH /passwords/:token` | Body: `password` (auth hash), `password_wrapped_key`, `recovery_wrapped_key`, and at most one of `blob { ciphertext, nonce }` or `wipe: true` (the recovery-code path sends neither). In one transaction: update the user, replace the blob if given, destroy it if `wipe`, destroy all sessions, start a new session. Responds JSON `200 { account }` so the client can proceed straight into the app. |
| `GET /api/sync`, `PUT /api/sync`, `POST /api/sync/reset` | `reset` is removed; the reset page replaces it. `show` and `update` are unchanged except `salt` is optional. |

The unauthenticated-access list gains nothing new: `PUT /api/account/keys`
requires a session; the passwords routes are already public and
token-gated.

## Client flows

A new `lib/keys.js` in `vendor/javascript/lib` owns derivation, wrapping,
unwrapping, recovery code generation, and the auth hash. `lib/db.js` gains a
`keys` object store (database version 3) holding the data key next to the
existing account stamp. `lib/crypto.js` keeps `encrypt`/`decrypt`; its
`deriveKey` is removed.

### Signup (`users/new`, new `signup_controller`)

Fields: email, password (with show/hide), invite code. On submit the
controller:

1. Validates the password length client-side.
2. Generates the data key and recovery code; derives the password and
   recovery wrapping keys; wraps the data key twice; derives the auth hash.
3. Posts `/users` as JSON. On 422, shows the server errors inline (bad or
   used invite code, duplicate email).
4. On success: stores the data key and account stamp in IndexedDB, then
   replaces the form with the **recovery code screen**: the code in large
   monospace text, a copy button (existing `clipboard_controller`), the
   line "If you forget your password, this code is the only way to get your
   entries back on a new phone. Save it somewhere safe.", and an "I've saved
   it" button that visits `/`.

### Login (`sessions/new`, new `login_controller`)

Fields: email, password. A real form with `autocomplete` attributes so
password managers keep working; the controller intercepts submit:

1. Derives the auth hash (about a second on a phone; the button shows
   "Signing in…").
2. Posts `/session` as JSON. On 401 shows "Try another email address or
   password." inline.
3. On 200: unwraps `password_wrapped_key` with the password wrapping key into
   a non-extractable data key, stores it with the account stamp, visits `/`.
   If unwrapping fails (data corrupted server-side), shows "Something is
   wrong with your account. Reset your password to continue." with a link to
   the reset page.

### App boot (`sync_controller`, replacing the unlock overlay)

1. Read the data key from IndexedDB. If absent, the server session has
   outlived the device key (site data cleared, or another account used this
   device). Run the existing logout wipe and send them to login: login is
   the only gate.
2. `GET /api/sync`. 404 → nothing to import (fresh signup); dispatch
   `app:unlocked`. 200 → decrypt with the data key, merge into local state
   (the stamp matches by construction), dispatch `app:unlocked`.
3. Decrypt failure means the blob was re-keyed elsewhere (a reset on another
   device). Show "Your password was changed on another device. Sign in
   again." and run the logout wipe. Nothing on this device is uploaded, so
   the newer blob is never overwritten with old-key ciphertext.

The save path is unchanged except it no longer sends `salt`.

### Forgot password (`passwords/edit`, new `password_reset_controller`)

Fields: new password (with show/hide), optional recovery code. Before the
form is usable the controller reads the account stamp and compares it to the
page's account id, then shows one of three warnings that update as the
recovery code field is filled or emptied:

- **Code entered:** "Your entries will be restored on this device."
- **No code, this device holds the account's data:** "Your entries on this
  device will be kept. Entries made on other devices since this one last
  synced won't be included."
- **No code, any other device:** "Without your recovery code, your encrypted
  backup will be permanently erased and you will start fresh."

On submit:

1. Derive the new password key and auth hash.
2. **Code path:** derive the recovery wrapping key, unwrap the page's
   `recovery_wrapped_key`. Failure → "That recovery code doesn't match."
   inline, nothing sent. Success → re-wrap the data key under the new
   password key; send `password`, `password_wrapped_key`, and the unchanged
   `recovery_wrapped_key`.
3. **Device path:** generate a new data key and recovery code, encrypt the
   exported local state under the new data key, wrap it twice; send
   `password`, both wrapped keys, and `blob`.
4. **Wipe path:** generate a new data key and recovery code, wrap it twice;
   send `password`, both wrapped keys, and `wipe: true`.
5. On 200: store the data key and stamp. Device and wipe paths then show the
   recovery code screen (a new code was made); the code path visits `/`
   directly.

### Settings screen

- **Change password.** Current password and new password. The client
  derives the auth hash for both, re-wraps the data key (already in memory)
  under the new password wrapping key, and sends `current_password`,
  `password`, and `password_wrapped_key`. The server verifies the current
  auth hash. On 200 nothing changes locally: the data key is the same.
- **New recovery code.** Asks for the current password, generates a code,
  wraps the data key under it, sends `current_password` and
  `recovery_wrapped_key`, then shows the recovery code screen.
- **Log out.** Unchanged.

### Removed

The unlock overlay and its markup in the layout, the passphrase reset panel,
`openResetPanel`/`performReset`/`unlock`/`discardOtherAccountData` in
`sync_controller.js`, `POST /api/sync/reset`, the password confirmation
field, `deriveKey` in `lib/crypto.js`, and every mention of "passphrase" in
views and mailers.

## Native readiness

The data key stored in IndexedDB is the object the future Face ID bridge
component wraps in the Keychain. Nothing in this design needs to change for
Hotwire Native.

## Testing

Server (Minitest):

- `User`: auth hash format accepted, raw password rejected, wrapped keys
  required and bounded.
- `SessionsController`: JSON success returns the wrapped key; JSON failure
  is 401; HTML fallback still redirects.
- `UsersController`: creates with wrapped keys; rejects missing keys, bad
  invite, duplicate email; existing race tests keep passing.
- `Api::AccountKeysController`: each field updates alone and together; wrong
  current password → 401 and nothing changes; password change destroys other
  sessions but not the current one; unauthenticated → 401.
- `PasswordsController#update`: code path leaves the blob alone; device path
  replaces it; wipe path destroys it; sessions reset; invalid token
  rejected; blank password rejected.
- `authentication_lockdown_test.rb`: add `PUT /api/account/keys` to the
  rejection list and remove `/api/sync/reset`.
- Launch migration: a test that the migration leaves the tables empty is
  not practical; verify by running it against a copy of production data
  before deploy.

Client: no JavaScript harness exists. The existing contract tests that pin
removed behavior (`client_unlock_contract_test.rb`,
`client_reset_contract_test.rb`) are deleted. A new
`client_keys_contract_test.rb` pins three properties statically: the JSON
bodies built by the login, signup, and reset controllers set `password` from
the derived auth hash and never from the form field, PBKDF2 uses at least
600000 rounds, and the data key is imported and unwrapped as
non-extractable. Manual verification
checklist, run in Safari on iOS and Chrome on desktop:

1. Sign up, save the recovery code, add an entry, reload: still unlocked,
   entry present.
2. Log out, log in on a second browser: entry present.
3. Forgot password with the recovery code on a third browser: entry
   present.
4. Forgot password without the code on the first browser: entry present,
   new code shown. Then the second browser, still open, reloads: sent to
   login with the "changed on another device" message.
5. Forgot password without the code on a fresh browser: wipe warning shown,
   after reset the app is empty.
6. Change password, log out, log in with the new password.
7. Submit the signup form with JavaScript disabled: the "requires
   JavaScript" error shows and no user row is created.

## Out of scope

- Multi-tenancy, counselor sign-in, and invite changes (project 2).
- Face ID and native key storage (project 6).
- Per-user random salts or a pre-login endpoint. Revisit if email changes
  are ever allowed.
- Migrating existing accounts. The launch clears them.
