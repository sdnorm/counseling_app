# Client-Side Auth Lockdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop journal/check-in data from being visible while logged out (bfcache restore, persistent IndexedDB, service-worker cache) while keeping offline PWA support.

**Architecture:** Server auth is already correct — all changes are client-side plus one pinning test. We add: a bfcache re-lock (reload on `pageshow` restore), a logout flow that wipes IndexedDB and service-worker caches before the session DELETE, a service-worker `logout` message handler, a guard so `navigation_controller.render()` no-ops until unlock, and an integration test pinning every protected route.

**Tech Stack:** Rails 8.1 (minitest, fixtures), Stimulus via importmap, vanilla service worker in `public/`, IndexedDB helpers in `vendor/javascript/lib/db.js` (pinned as `lib/db`).

**Spec:** `docs/superpowers/specs/2026-07-30-client-side-auth-lockdown-design.md`

**Context for the engineer (read first):**
- Screens at `/screens/:id` are empty HTML templates rendered `layout: false`; all user data lives client-side in IndexedDB (`crossroads_app` DB) and is rendered in by Stimulus controllers.
- The unlock overlay (`#unlock-overlay` in `app/views/layouts/application.html.erb`) is controlled by `app/javascript/controllers/sync_controller.js`, which dispatches `app:unlocked` after passphrase verification.
- `test/test_helper.rb` provides `sign_in_as(user, password: "password")`; fixtures `users(:danny)` / `users(:maria)` exist with password `"password"`.
- There is no JS test harness in this repo — JS tasks are verified by `bin/ci` still passing (asset pipeline / no syntax breakage) and the manual checklist in Task 7. Do not add a JS test framework.

---

### Task 1: Server-side auth regression test

Pins today's correct server behavior. This test passes immediately — that is its purpose (regression guard). Still run it before committing to verify it passes for the right reasons.

**Files:**
- Create: `test/integration/authentication_lockdown_test.rb`

- [ ] **Step 1: Write the test**

```ruby
require "test_helper"

class AuthenticationLockdownTest < ActionDispatch::IntegrationTest
  # Must match valid_screens in ScreensController#show
  SCREENS = %w[journal gratitude emotions coping triangle checkin takeaways agenda resources settings]

  test "root requires authentication" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "every screen requires authentication" do
    SCREENS.each do |id|
      get screen_path(id)
      assert_redirected_to new_session_path, "expected /screens/#{id} to redirect to login"
    end
  end

  test "sync api requires authentication" do
    get api_sync_path, headers: { "Accept" => "application/json" }
    assert_response :unauthorized

    put api_sync_path, params: { blob: { ciphertext: "x", nonce: "n", salt: "s" } }, as: :json
    assert_response :unauthorized
  end

  test "push api requires authentication" do
    post api_push_path, params: { endpoint: "https://push.example/e" }, as: :json
    assert_response :unauthorized

    delete api_push_path, params: { endpoint: "https://push.example/e" }, as: :json
    assert_response :unauthorized

    patch "/api/push/preferences", params: { reminder_time: "09:00" }, as: :json
    assert_response :unauthorized
  end

  test "admin invites require http basic auth" do
    get admin_invites_path
    assert_response :unauthorized
  end

  test "intentionally public routes stay public" do
    get new_session_path
    assert_response :success

    get new_password_path
    assert_response :success

    get new_user_path
    assert_response :success

    get "/api/push/vapid_public_key"
    assert_response :success
  end

  test "authenticated user can access screens and sync" do
    sign_in_as users(:danny)

    get screen_path("journal")
    assert_response :success

    get api_sync_path, headers: { "Accept" => "application/json" }
    assert_includes [ 200, 404 ], response.status  # 404 = no blob saved yet, still authenticated
  end
end
```

- [ ] **Step 2: Run the test**

Run: `bin/rails test test/integration/authentication_lockdown_test.rb`
Expected: 7 runs, 0 failures. If any assertion fails, STOP — that is a real server-side auth hole; report it rather than adjusting the test.

- [ ] **Step 3: Commit**

```bash
git add test/integration/authentication_lockdown_test.rb
git commit -m "test: pin authentication requirements for all routes"
```

---

### Task 2: `wipeAll()` in lib/db

**Files:**
- Modify: `vendor/javascript/lib/db.js` (append at end of file)

**Why this shape:** every helper in this file opens a fresh IndexedDB connection and never closes it, so `indexedDB.deleteDatabase` alone would hang in `onblocked`. Instead, clear every object store in one transaction (works despite open connections), then attempt `deleteDatabase` best-effort without awaiting it.

- [ ] **Step 1: Append `wipeAll` to `vendor/javascript/lib/db.js`**

```js
export async function wipeAll() {
  const db = await openDB();
  const stores = Array.from(db.objectStoreNames);
  await new Promise((resolve, reject) => {
    const tx = db.transaction(stores, "readwrite");
    stores.forEach((name) => tx.objectStore(name).clear());
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
  db.close();
  // Best-effort: removes the database entirely once other connections close.
  indexedDB.deleteDatabase(DB_NAME);
}
```

- [ ] **Step 2: Commit**

```bash
git add vendor/javascript/lib/db.js
git commit -m "feat: add wipeAll to clear all IndexedDB stores"
```

---

### Task 3: Service worker logout handler

**Files:**
- Modify: `public/service-worker.js`

- [ ] **Step 1: Bump the cache version**

Change line 1:

```js
const CACHE_NAME = "crossroads-v5";
```

(was `"crossroads-v4"` — bumping forces clients onto the updated worker's cache.)

- [ ] **Step 2: Add the message listener**

Append after the existing `fetch` listener (before the `push` listener):

```js
self.addEventListener("message", (event) => {
  if (event.data?.type !== "logout") return;
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(names.map((name) => caches.delete(name))))
      .then(() => event.ports[0]?.postMessage({ ok: true }))
  );
});
```

- [ ] **Step 3: Commit**

```bash
git add public/service-worker.js
git commit -m "feat: clear all service worker caches on logout message"
```

---

### Task 4: Logout controller wipes client data

**Files:**
- Create: `app/javascript/controllers/logout_controller.js`
- Modify: `app/views/screens/settings.html.erb:31` (the `button_to "Log Out"` line)

**How it works:** the Stimulus controller sits on the `button_to` form. On submit it prevents the default, wipes IndexedDB and service-worker caches (bounded by a timeout so logout can never hang), then calls the form element's native `submit()` — which bypasses submit listeners (no recursion) and performs a full-page DELETE to `/session`, landing on the login page. Stimulus eager-loads controllers, so it connects even though the settings screen is injected into the DOM by `navigation_controller`. The spec's "clear in-memory key material" step is satisfied by the full-page navigation itself — the entire JS heap (including the sync controller's `key`/`salt`) is destroyed, so no explicit `clear()` call is needed.

- [ ] **Step 1: Create `app/javascript/controllers/logout_controller.js`**

```js
import { Controller } from "@hotwired/stimulus";
import { wipeAll } from "lib/db";

// Wipes client-side data (IndexedDB + service worker caches) before the
// session DELETE submits, so nothing readable remains on the device.
export default class extends Controller {
  async submit(event) {
    event.preventDefault();
    try {
      await Promise.all([wipeAll(), this.clearServiceWorkerCaches()]);
    } catch (e) {
      console.error("Logout cleanup failed:", e);
    }
    this.element.submit();
  }

  clearServiceWorkerCaches() {
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
}
```

- [ ] **Step 2: Attach it to the logout form in `app/views/screens/settings.html.erb`**

Replace:

```erb
<%= button_to "Log Out", session_path, method: :delete, class: "btn btn-o" %>
```

with:

```erb
<%= button_to "Log Out", session_path, method: :delete, class: "btn btn-o",
      form: { data: { controller: "logout", action: "submit->logout#submit" } } %>
```

- [ ] **Step 3: Verify nothing broke server-side**

Run: `bin/rails test`
Expected: all tests pass (this change is view + JS only).

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/logout_controller.js app/views/screens/settings.html.erb
git commit -m "feat: wipe IndexedDB and SW caches on logout"
```

---

### Task 5: Re-lock on bfcache restore

**Files:**
- Modify: `app/javascript/controllers/sync_controller.js:6-12` (`connect()`)

- [ ] **Step 1: Add the `pageshow` handler to `connect()`**

Replace the existing `connect()`:

```js
  connect() {
    this.key = null;
    this.salt = null;
    this.unlocked = false;
    document.addEventListener("sync:save", () => this.save());
    // A bfcache restore would revive the unlocked DOM (decrypted entries,
    // hidden overlay) after logout. Force a clean boot instead.
    window.addEventListener("pageshow", (event) => {
      if (event.persisted) window.location.reload();
    });
    this.showUnlockScreen();
  }
```

(Only the `pageshow` listener and its comment are new; everything else is unchanged.)

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/sync_controller.js
git commit -m "fix: reload on bfcache restore so unlocked state never survives logout"
```

---

### Task 6: Guard navigation rendering behind unlock

**Files:**
- Modify: `app/javascript/controllers/navigation_controller.js:8-17` (`connect()`) and `:90` (`render()`)

- [ ] **Step 1: Track unlock state in `connect()`**

Replace the existing `connect()`:

```js
  connect() {
    this.currentValue = "home";
    this.userName = "";
    this.appUnlocked = false;
    // Wait for the sync controller to unlock before rendering
    document.addEventListener("app:unlocked", async () => {
      this.appUnlocked = true;
      const profile = await getAll("profile");
      this.userName = profile.find(p => p.id === "name")?.value || "";
      this.render();
    });
  }
```

- [ ] **Step 2: Guard `render()`**

Add as the first line of the existing `render()` method:

```js
  render() {
    if (!this.appUnlocked) return;
```

(The rest of `render()` is unchanged.)

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/navigation_controller.js
git commit -m "fix: navigation render no-ops until app is unlocked"
```

---

### Task 7: Full CI + manual verification

- [ ] **Step 1: Run full CI**

Run: `bin/ci`
Expected: all green (tests, rubocop, security scans). Fix anything it flags before proceeding.

- [ ] **Step 2: Manual browser verification**

Run `bin/dev`, open the app in a browser, and walk through:

1. Log in, unlock with passphrase, open My Journal — entries visible.
2. Settings → Log Out. In devtools → Application: IndexedDB `crossroads_app` stores are empty (or DB gone) and Cache Storage has no `crossroads-*` caches.
3. Press the Back button — the page must NOT show journal content (it reloads and redirects to login).
4. Log in + unlock again (data re-syncs from server), then in devtools → Network switch to Offline and reload — app shell loads, unlock overlay shows, and unlocking restores access. Switch back online.

Expected: all four hold. If step 3 shows content, the bfcache reload (Task 5) is not firing — debug there, do not proceed.

- [ ] **Step 3: Update the spec status line**

In `docs/superpowers/specs/2026-07-30-client-side-auth-lockdown-design.md`, change:

```markdown
**Status:** Approved design, pending implementation plan
```

to:

```markdown
**Status:** Implemented (see docs/superpowers/plans/2026-07-30-client-side-auth-lockdown.md)
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-07-30-client-side-auth-lockdown-design.md
git commit -m "docs: mark client-side auth lockdown spec implemented"
```
