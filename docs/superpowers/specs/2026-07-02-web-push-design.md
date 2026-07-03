# Web Push Notifications — Design

**Date:** 2026-07-02
**Status:** Approved by Spencer (reminder time stored server-side; daily gratitude reminder is the full scope)

## Goal

Finish the Web Push feature: users can enable push notifications from the Settings
screen and receive a daily gratitude reminder at the time they chose, delivered via
Web Push (VAPID). Dead subscriptions are cleaned up automatically.

## Context and constraint

The VAPID keypair, `Api::PushController` (subscribe/unsubscribe/public-key endpoints),
`PushSubscription` model, routes, service worker `push` handler, and Stimulus
`push_controller.js` are already on `main`.

The app is local-first and E2E-encrypted: settings (including "Gratitude Reminder
Time") live in IndexedDB and sync only as an encrypted blob, so the server cannot
read them. To schedule per-user reminders, the client sends the reminder time and
browser timezone to the server in plaintext. This is accepted low-sensitivity
metadata; journal content stays E2E-encrypted, and push payloads carry only a
generic reminder message.

## Components

### 1. Reminder preferences (server-side)

- Migration adds to `users`:
  - `reminder_time` — string, "HH:MM" 24-hour format, nullable (null = no reminder)
  - `time_zone` — string, IANA name (e.g. "America/Chicago"), nullable
  - `last_reminded_on` — date, nullable; stamps the user's local date of the last send
- `User` validates `reminder_time` format (`/\A([01]\d|2[0-3]):[0-5]\d\z/`) and that
  `time_zone` is a valid IANA identifier (`ActiveSupport::TimeZone`), both allowing nil.
- New endpoint `PATCH /api/push/preferences` (same `Api::PushController`):
  accepts `reminder_time` and `time_zone`, updates `current_user`. Sending a null
  `reminder_time` clears the reminder.

### 2. Push sender — `PushNotifier` service

`app/services/push_notifier.rb`

- `PushNotifier.notify(user, title:, body:)`
- Iterates `user.push_subscriptions`; for each, calls `WebPush.payload_send` with:
  - `message:` JSON `{ title:, body: }` (matches what `public/service-worker.js`
    already parses in its `push` handler — verify the exact shape during implementation
    and adapt whichever side is cheaper)
  - `endpoint:`, `p256dh:`, `auth:` from the record
  - `vapid:` `{ subject: "mailto:spencernorman@hey.com", public_key:, private_key: }`
    with keys from `Rails.application.credentials.dig(:web_push, ...)`
- Rescues `WebPush::ExpiredSubscription` and `WebPush::InvalidSubscription`
  (gem's 410/404 errors) → destroys that subscription record. Other
  `WebPush::ResponseError`s are logged and skipped (do not raise out of the loop).

### 3. Scheduling — recurring job

`app/jobs/send_gratitude_reminders_job.rb` → `SendGratitudeRemindersJob`

- Registered in `config/recurring.yml` (production): `schedule: every 5 minutes`.
- Logic: for each user with `reminder_time` and `time_zone` present and at least one
  push subscription:
  - Compute `now_local = Time.current.in_time_zone(user.time_zone)`
  - Due when `now_local.strftime("%H:%M") >= reminder_time` AND
    (`last_reminded_on` is nil or `< now_local.to_date`)
  - When due: `PushNotifier.notify(user, title: "Gratitude time", body: "Take a moment
    for your gratitude practice.")` then update `last_reminded_on = now_local.to_date`.
- "Has passed the time today" rather than "matches the current 5-minute window" makes
  the job self-healing across missed runs, deploys, and DST shifts. Worst-case delay
  is one schedule interval (5 minutes).

### 4. Settings UI integration

`app/views/screens/settings.html.erb` + `push_controller.js` + `settings_controller.js`

- Add to the settings card a checkbox: "Enable push notifications", wired to a new
  `push` Stimulus controller scope (`data-controller="settings push"` on the wrapper
  or a nested element — follow existing markup style).
- `push_controller.js` changes:
  - `connect()`: reflect current state — checked if `pushManager.getSubscription()`
    returns a subscription; if `Notification.permission === "denied"`, disable the
    toggle and show a hint ("Notifications are blocked in your browser settings").
    Hide the toggle entirely if `!("PushManager" in window)`.
  - `toggle()` action on the checkbox `change` event (a user gesture): calls existing
    `subscribe()` / `unsubscribe()`. On subscribe failure (permission dismissed or
    denied), revert the checkbox and show the hint.
- `settings_controller.js#save`: in addition to the existing IndexedDB writes, always
  send `PATCH /api/push/preferences` with
  `{ reminder_time: <input value>, time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone }`.
  Subscribe flow also sends preferences once after a successful subscription so a
  user who never re-saves settings still gets a reminder time registered.

### 5. Error handling summary

- 410/404 from push service → destroy `PushSubscription` (in `PushNotifier`).
- Other push errors → log, continue with remaining subscriptions.
- Permission denied in browser → toggle disabled with hint; no server call.
- VAPID key rotation (operational note): rotating keys invalidates all browser
  subscriptions; users must re-subscribe. No code handles this — documented risk.

### 6. Tests (minitest; suite is currently empty)

- `PushSubscription` model: presence validations.
- `User` model: reminder_time / time_zone format validations.
- `Api::PushController`: vapid_public_key (no auth), create (new + upsert by
  endpoint), destroy (found + not found), preferences update, auth required.
- `PushNotifier`: sends payload per subscription (WebPush stubbed); destroys record
  on `WebPush::ExpiredSubscription` / `InvalidSubscription`; continues loop on other
  errors.
- `SendGratitudeRemindersJob` with `travel_to`: sends when local time passed and not
  yet reminded today; skips when already reminded, when before time, when no
  subscriptions, when no reminder_time; timezone correctness (user in a zone ahead
  of/behind UTC).

## Out of scope

- Any notification triggers beyond the daily gratitude reminder.
- VAPID key rotation handling.
- Per-user notification content (payloads stay generic by design).
