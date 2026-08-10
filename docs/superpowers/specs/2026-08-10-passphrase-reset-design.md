# Passphrase Reset (Forgot Passphrase)

**Date:** 2026-08-10
**Status:** Approved

## Problem

A client forgot her passphrase but still knows her account password. Today the
unlock screen is a dead end: "Your data cannot be recovered. Contact your
counselor for a new account." She tried starting over with a new email and
still could not get to a working state.

The data is end-to-end encrypted — the server stores only a ciphertext blob
(`EncryptedBlob`), keyed by a PBKDF2-derived key that never leaves the device —
so the server genuinely cannot recover it. But the device she has been using
holds the full decrypted state in IndexedDB (the documented offline trade-off
in `2026-07-30-client-side-auth-lockdown-design.md`). Forgetting the
passphrase therefore does not have to mean losing data: the device can
re-encrypt what it already holds under a new passphrase.

## Decision

Add a "Forgot your passphrase?" flow to the unlock screen, gated by the
account password:

- **On a device that holds this account's data** (IndexedDB account stamp
  matches), reset re-keys: the client encrypts its local state under a new
  passphrase and replaces the server blob. No data loss.
- **On any other device** (no local data for this account), reset wipes: the
  server blob is deleted after an explicit destructive warning, and the user
  starts fresh on the existing first-time path.

### Security model — unchanged

- Re-keying happens entirely in the browser: new random salt, same
  `deriveKey`/`encrypt` path used on every save today. The new passphrase and
  key never leave the device; the server receives only ciphertext.
- The account password authorizes replacing/deleting the blob. It has no
  cryptographic relationship to the data; the server, its operators, and
  anyone breaching it still see only ciphertext.
- Accepted nuance: on a device that already holds the data, someone knowing
  the account password could reset and view that device's data. That device
  already exposes its plaintext to anyone with device access (devtools), so
  the hard guarantee — server-side zero knowledge — is unaffected.
- Accepted risk (out of scope): another device still unlocked with the old
  passphrase can later overwrite the new blob with old-key ciphertext via its
  normal save path. Clients here are effectively single-device; revisit if
  that changes.

## Design

### 1. Server: `POST /api/sync/reset`

New action on `Api::SyncController` (route: `post :reset` under
`resource :sync`). Parameters:

- `password` (required) — verified with `current_user.authenticate`. Wrong
  password → 401 JSON error, nothing changes.
- `blob: { ciphertext, nonce, salt }` (optional) —
  - present → replace: update-or-build `current_user.encrypted_blob` with the
    new blob (same validations as `update`).
  - absent → wipe: `current_user.encrypted_blob&.destroy`, return success.

Rate limited like login (`to: 10, within: 3.minutes`, keyed by user id) so the
endpoint cannot be used to guess passwords faster than `SessionsController#create`
allows. The existing `update` rate limit stays as is.

### 2. Unlock screen UI

Replace the dead-end footer text with a "Forgot your passphrase?" link that
swaps the unlock card for a reset panel:

- Account password field.
- New passphrase field, with the existing first-time warning ("Write it
  down — it cannot be recovered.").
- A warning line chosen by path (see below) and a "Reset passphrase" button,
  plus a "Back" link to the normal unlock card.

Markup lives in the layout next to the existing overlay elements; behavior in
`sync_controller.js`, which already owns the unlock lifecycle.

### 3. Client flow (`sync_controller.js`)

On opening the reset panel:

1. `GET /api/sync` to learn `account` (present on both 200 and 404 responses).
2. Compare `readAccountStamp()` to `account`.
3. **Stamp matches** → re-key path. Warning: "Your entries on this device will
   be kept. Entries made on other devices since this one last synced won't be
   included."
   On submit: generate new salt, `deriveKey(newPassphrase, salt)`,
   `encrypt(await exportState(), key)`, then `POST /api/sync/reset` with
   password + blob. On success: set `this.key/this.salt`, hide overlay, mark
   unlocked, dispatch `app:unlocked`.
4. **No matching stamp** → wipe path. Warning: "This permanently erases your
   encrypted backup. Your entries cannot be recovered." On submit:
   `POST /api/sync/reset` with password only. On success: run the existing
   first-time path (`discardOtherAccountData(account)`, new salt/key from the
   new passphrase, write stamp, unlocked). The next save uploads the new blob.
5. Wrong password (401 from reset) → inline error, panel stays open, local
   data untouched. Rate-limit response (429) → "Too many attempts. Try again
   later."

### 4. Copy change

The unlock footer's "Contact your counselor for a new account" is removed —
the reset flow replaces it. First-time copy is unchanged.

## Out of scope

- Recovering the old blob once wiped (no archive/soft-delete; the blob is
  ciphertext we could never decrypt anyway, and keeping it invites confusion).
- Multi-device conflict handling after reset (noted above as accepted risk).
- Changing the encryption scheme, key derivation, or unlock gate behavior.
- Whatever prevented the client's "new email" workaround — being verified
  separately against the fixes in #29–#31; any remaining bug gets its own fix.

## Testing

- Controller tests: reset with correct password replaces the blob; reset
  without blob destroys it; wrong password → 401 and blob unchanged;
  unauthenticated → 401. The rate limit is verified manually in development
  (`:memory_store`) — the test env's `:null_store` cache makes `rate_limit`
  inert there, which is also why the login limiter has no test.
- Client behavior verified manually: re-key on a stamped device keeps entries
  and unlocks; wipe path on a fresh device warns and starts over; wrong
  password shows the inline error and changes nothing.
- Existing `authentication_lockdown_test.rb` gains `/api/sync/reset` in its
  unauthenticated-rejection list.
