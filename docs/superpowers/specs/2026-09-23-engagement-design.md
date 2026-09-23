# Engagement: Days Active

**Date:** 2026-09-23
**Status:** Approved
**Part of:** `2026-09-16-pivot-roadmap.md`, project 3
**Depends on:** `2026-09-22-multi-tenancy-design.md`

## Problem

Counselors need to know whether clients are using the app, so they can tell
if it is bringing value. The server must learn nothing about what a client
wrote. Today the dashboard shows only "last active".

## Decisions

- Record **days active only**: a client who synced on a calendar day was
  active that day. No counts, no tools, no content. No opt-in is needed
  because nothing about what they did is recorded.
- Clients see their own strip and streak on Home, with a line saying the
  counselor sees the same thing and nothing more.
- Tool-level opt-in, digests, and exports are out of scope.

## Design

### Recording

`activity_days`: `user_id`, `day` (date), timestamps, unique index on
`[user_id, day]`. `User#touch_last_synced!` (called after every successful
sync) gains the upsert: it computes today in the client's time zone
(`time_zone` when set for reminders, else `Time.zone`) and upserts one row
in a single statement. The existing ten-minute throttle now skips only when
the last sync was within ten minutes **and** on the same local day, so
midnight is never missed. Archived clients keep being recorded: the active
count depends on it.

### Summaries

`Engagement`, a table-less value object built from a client's local today
and its active dates in the last 30 days:

- `week`: seven `[date, active?]` pairs ending today.
- `active_last_30`: count of active dates in the window.
- `streak`: consecutive active days ending today, or ending yesterday if
  today has no sync yet; 0 otherwise.
- `last_active_on`: the latest active date, or nil.
- `to_h`: the JSON shape the client Home reads.

`Engagement.for(client, days: nil)` loads the window itself; the dashboard
passes preloaded rows for all listed clients so the list runs one query for
activity regardless of client count.

### Counselor dashboard

The client list gains a seven-day dot strip (Mon–Sun initials, filled dot
for active), "N of 30", and streak, beside last active. Archived rows are
unchanged. Under the heading: "You see which days each client used the app,
never what they wrote."

### Client Home

The application layout embeds `<script id="activity-summary"
type="application/json">` with the client's `Engagement#to_h`. The Home
renderer shows the strip and "N of the last 30 days · streak N" above the
tiles with: "Your counselor sees this too: which days you used the app,
never what you wrote." Offline, the cached page shows the last summary.

### Retention

`PruneActivityDaysJob` deletes rows older than 400 days, scheduled daily in
`config/recurring.yml` (production).

## Testing

- Model: one row per local day, midnight boundary in a non-UTC zone, throttle
  skips within ten minutes on the same day but not across days, upsert is
  idempotent, streak and week arithmetic including the "yesterday" rule.
- Sync controller: a successful save creates the row; a rejected save does
  not.
- Dashboard: strip, "N of 30", streak render; query count does not grow with
  the number of clients.
- Home: the layout embeds the JSON for a logged-in client and not on the
  login page; a contract test pins that `navigation_controller.js` reads
  `activity-summary`.
- Prune job: deletes only rows older than 400 days.

## Out of scope

Tool-level opt-in, weekly digest emails, exports, per-practice retention
settings.
