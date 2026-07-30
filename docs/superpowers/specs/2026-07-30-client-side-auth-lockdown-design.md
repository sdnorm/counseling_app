# Client-Side Auth Lockdown

**Date:** 2026-07-30
**Status:** Approved design, pending implementation plan

## Problem

Journal/check-in content was observed on screen while logged out. Server-side
authentication is correct and verified: every route except login, password
reset, invite-gated signup, and the VAPID public key endpoint requires a
session (`Authentication` concern, `before_action :require_authentication`;
manually confirmed `/` and `/screens/:id` return 302 to `/session/new` without
a cookie).

The exposure is entirely client-side, from four compounding gaps:

1. **bfcache restore (primary reproduction).** No `pageshow`/`pagehide`
   handling exists. After logout, pressing Back can restore the fully
   unlocked DOM — decrypted entries rendered, unlock overlay hidden —
   from the browser's back-forward cache.
2. **Plaintext data persists in IndexedDB.** After passphrase unlock,
   `importState` writes all stores (journalEntries, gratitudeEntries,
   emotionSnapshots, copingSkills, triangleSnaps, checkinEntries, takeaways,
   agendaItems, profile, settings) to IndexedDB unencrypted. Logout
   (`SessionsController#destroy`) only terminates the server session; nothing
   ever clears IndexedDB.
3. **Service worker cache persists after logout.** `public/service-worker.js`
   pre-caches `/` and caches all screen HTML with an offline cache fallback.
   Caches are never cleared on logout, so a logged-out user can load the app
   shell offline, and its Stimulus controllers read the persisted IndexedDB
   data.
4. **Screen controllers load data on `connect()` unconditionally** (e.g.
   `journal_controller.js` calls `loadEntries()` in `connect()`). The unlock
   gate in `navigation_controller` (waits for `app:unlocked` before rendering)
   protects the normal flow, but any path that attaches a screen to the DOM
   without going through it renders data immediately.

## Decision

Lock down the client while keeping offline PWA support ("lock down, keep
offline"). Screen HTML templates at `/screens/*` contain no user data — all
sensitive data lives in IndexedDB — so the service worker may keep caching
templates; the unlock gate and logout wipe protect the data.

**Accepted trade-off:** between sessions, decrypted data remains in IndexedDB
on the device (readable via devtools by someone with device access). This is
the price of offline access. The unlock gate protects the casual
shared-device case, and logout fully wipes the device.

## Design

### 1. Re-lock on bfcache restore

In `sync_controller.js` (owner of the unlock lifecycle), listen for
`pageshow`. When `event.persisted` is true, force a full reload
(`location.reload()`). The reload lands on the normal boot path: server
session check, unlock overlay, no data rendered. Reload-on-restore is chosen
over in-place re-locking because it guarantees no decrypted state (DOM, JS
memory, Stimulus controller state) survives.

### 2. Wipe client data on logout

The settings screen's "Log Out" `button_to` gains a Stimulus controller
action that runs before the form submits:

1. Delete the IndexedDB database (`indexedDB.deleteDatabase`).
2. Send `{ type: "logout" }` to the service worker via `postMessage` and
   await its acknowledgment (bounded by a short timeout so logout never
   hangs).
3. Clear in-memory key material (`sync` controller's `clear()`).
4. Submit the DELETE to `/session` (existing server-side
   `terminate_session`).

Nothing is lost by wiping: the server holds the encrypted blob; next login
re-syncs and decrypts with the passphrase.

### 3. Service worker: clear caches on logout

Add a `message` listener to `public/service-worker.js`: on
`{ type: "logout" }`, delete all caches and reply with an acknowledgment.
Bump `CACHE_NAME`. Existing fetch behavior (network-first for HTML with
offline cache fallback, cache-first for static assets) is unchanged —
offline access still works, but only until logout and always behind the
unlock overlay.

### 4. Harden the unlock gate

Keep the existing `app:unlocked` flow as the single gate. Ensure every path
that can attach screen content to the DOM goes through it — today that is
`navigation_controller` (`render`/`loadScreen`, the bottom nav, and the
"more" menu). Guard `render()` so it no-ops until unlocked, making future
call sites safe by default rather than relying on callers.

### 5. Server-side regression tests

Integration test (`test/integration/authentication_lockdown_test.rb`)
asserting unauthenticated requests are rejected (302 to login, or 401 for
JSON) for: `/`, every valid screen id under `/screens/:id`, `GET/PUT
/api/sync`, `POST/DELETE /api/push`, `PATCH /api/push/preferences`, and
`/admin/invites` (401 HTTP Basic). Also asserts the intentional public
routes stay public: `/session/new`, `/passwords/new`, `/users/new`,
`/api/push/vapid_public_key`. This pins today's correct server behavior
against regressions.

## Out of scope

- Memory-only decrypted state (no IndexedDB persistence) — rejected for now;
  it would remove offline access and require refactoring all screen
  controllers.
- Idle/auto re-lock timers.
- Changes to the passphrase/E2E encryption scheme.

## Testing

- New integration test above runs in `bin/ci`.
- Manual verification: unlock → log out → Back button shows no data (reload
  to login); IndexedDB and Cache Storage empty in devtools after logout;
  offline reload while logged in still works behind the unlock overlay.
