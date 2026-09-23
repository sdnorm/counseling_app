# Engagement (Days Active) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record which calendar days each client used the app and show a week strip, 30-day count, and streak to the counselor and to the client.

**Architecture:** One `activity_days` row per client per local day, upserted by the sync endpoint through the existing throttle. A table-less `Engagement` value object turns rows into the strip, count, and streak. The dashboard preloads rows for all listed clients; the client layout embeds the client's own summary as JSON for the Home screen.

**Tech Stack:** Rails 8.1, SQLite upsert, Minitest, Stimulus.

**Spec:** `docs/superpowers/specs/2026-09-23-engagement-design.md`

---

## How this plan is executed

Same as the multi-tenancy plan: shared checkout on `product-ready`, file
lanes, one commit per task with `git add <own files> && git commit -m ...`,
retry on `index.lock`, never stash, never `git add -A`, never push, private
test DB via `DATABASE_URL=sqlite3:/private/tmp/<lane>-test.sqlite3 bin/rails test`
if SQLite locks.

| Lane | Agent | Owns |
|---|---|---|
| Foundation | driver | migration, `db/schema.rb`, `app/models/activity_day.rb`, `app/models/engagement.rb`, `app/models/user.rb`, `test/models/**`, `test/fixtures/activity_days.yml` |
| T — sync and client Home | pi | `app/controllers/api/sync_controller.rb`, `app/views/layouts/application.html.erb`, `app/views/shared/_activity_summary.html.erb`, `app/javascript/controllers/navigation_controller.js`, `app/assets/stylesheets/application.css`, `test/controllers/api/sync_controller_test.rb`, `test/integration/client_activity_summary_test.rb` |
| C — dashboard | codex | `app/controllers/dashboard/clients_controller.rb`, `app/views/dashboard/clients/index.html.erb`, `app/assets/stylesheets/counselor.css`, `test/controllers/dashboard/clients_controller_test.rb` |
| P — retention | grok | `app/jobs/prune_activity_days_job.rb`, `config/recurring.yml`, `test/jobs/prune_activity_days_job_test.rb`, `README.md` |

## Contract

```ruby
ActivityDay                      # belongs_to :user; columns user_id, day
User#activity_days
User#local_time_zone             # ActiveSupport::TimeZone
User#local_today                 # Date
User#touch_last_synced!          # now also upserts today's ActivityDay

Engagement.for(user, days: nil)  # days: Array<Date> preloaded, optional
Engagement::WINDOW               # 30
engagement.week                  # [[Date, true/false] x 7], oldest first, ends today
engagement.active_last_30        # Integer
engagement.streak                # Integer
engagement.last_active_on        # Date or nil
engagement.to_h                  # { week: [{ date: "YYYY-MM-DD", active: bool }], active_last_30:, streak:, last_active_on: "YYYY-MM-DD" | nil }
```

The layout embeds `<script type="application/json" id="activity-summary">`
with `engagement.to_h.to_json` only when a client is logged in.

---

## Foundation (driver)

### Task F1: Table, models, user hooks, tests

**Files:**
- Create: `db/migrate/20260923000001_create_activity_days.rb`
- Create: `app/models/activity_day.rb`, `app/models/engagement.rb`
- Modify: `app/models/user.rb`
- Create: `test/fixtures/activity_days.yml` (empty), `test/models/activity_day_test.rb`, `test/models/engagement_test.rb`
- Modify: `test/models/user_test.rb`

- [ ] **Step 1: Migration**

```ruby
# db/migrate/20260923000001_create_activity_days.rb
class CreateActivityDays < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_days do |t|
      t.references :user, null: false, foreign_key: true
      t.date :day, null: false
      t.timestamps
    end
    add_index :activity_days, [ :user_id, :day ], unique: true
  end
end
```

- [ ] **Step 2: Models**

```ruby
# app/models/activity_day.rb
#
# "This client used the app on this day." Nothing else is recorded: no
# counts, no screens, no content. One row per client per local day.
class ActivityDay < ApplicationRecord
  belongs_to :user
  validates :day, presence: true, uniqueness: { scope: :user_id }
end
```

```ruby
# app/models/engagement.rb
#
# Turns a client's active dates into what the counselor and the client see:
# a week strip, a 30-day count, and a streak. Pure value object; pass
# preloaded dates from the dashboard so a list of clients costs one query.
class Engagement
  WINDOW = 30

  attr_reader :today

  def self.for(user, days: nil)
    today = user.local_today
    days ||= user.activity_days.where(day: (today - (WINDOW - 1))..today).pluck(:day)
    new(days, today: today)
  end

  def initialize(days, today:)
    @today = today
    @days = days.to_set
  end

  def week
    ((today - 6)..today).map { |date| [ date, @days.include?(date) ] }
  end

  def active_last_30
    @days.count { |date| date > today - WINDOW && date <= today }
  end

  # Consecutive active days ending today, or ending yesterday when today has
  # no sync yet, so a streak doesn't read as broken before the day is over.
  def streak
    start = if @days.include?(today) then today
            elsif @days.include?(today - 1) then today - 1
            end
    return 0 unless start
    count = 0
    while @days.include?(start - count)
      count += 1
    end
    count
  end

  def last_active_on
    @days.max
  end

  def to_h
    {
      week: week.map { |date, active| { date: date.iso8601, active: active } },
      active_last_30: active_last_30,
      streak: streak,
      last_active_on: last_active_on&.iso8601
    }
  end
end
```

`app/models/user.rb`: add `has_many :activity_days, dependent: :destroy` after `has_one :practice`, and replace `touch_last_synced!` with:

```ruby
  def local_time_zone
    ActiveSupport::TimeZone[time_zone.to_s] || Time.zone
  end

  def local_today
    Time.current.in_time_zone(local_time_zone).to_date
  end

  # Called on every successful sync. One write per ten minutes is plenty for
  # a 30-day window, but a new local day always records, so a streak can't
  # miss midnight. Days active is the only engagement signal ever stored.
  def touch_last_synced!
    today = local_today
    if last_synced_at && last_synced_at > 10.minutes.ago && last_synced_at.in_time_zone(local_time_zone).to_date == today
      return
    end
    update_column(:last_synced_at, Time.current)
    ActivityDay.upsert({ user_id: id, day: today }, unique_by: %i[user_id day])
  end
```

- [ ] **Step 3: Tests**

`test/fixtures/activity_days.yml`: a file containing only `# none` so the table is truncated between tests.

```ruby
# test/models/activity_day_test.rb
require "test_helper"

class ActivityDayTest < ActiveSupport::TestCase
  test "touch_last_synced! records today once and is idempotent" do
    user = users(:danny)
    user.touch_last_synced!
    user.update_column(:last_synced_at, 11.minutes.ago)
    user.touch_last_synced!
    assert_equal [ user.local_today ], user.activity_days.pluck(:day)
  end

  test "the throttle skips within ten minutes on the same day but not across midnight" do
    user = users(:danny)
    user.update!(time_zone: "America/Chicago")
    travel_to Time.zone.parse("2026-09-23 04:55 UTC") do   # 23:55 the previous day in Chicago
      user.touch_last_synced!
    end
    travel_to Time.zone.parse("2026-09-23 05:02 UTC") do   # 00:02 Chicago, 7 minutes later
      user.touch_last_synced!
    end
    assert_equal [ Date.new(2026, 9, 22), Date.new(2026, 9, 23) ], user.activity_days.order(:day).pluck(:day)
  end

  test "day is unique per user" do
    user = users(:danny)
    user.activity_days.create!(day: Date.current)
    assert_raises(ActiveRecord::RecordInvalid) { user.activity_days.create!(day: Date.current) }
  end
end
```

```ruby
# test/models/engagement_test.rb
require "test_helper"

class EngagementTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 9, 23)

  def engagement(*offsets)
    Engagement.new(offsets.map { |n| TODAY - n }, today: TODAY)
  end

  test "week is seven pairs ending today" do
    week = engagement(0, 2).week
    assert_equal 7, week.size
    assert_equal [ TODAY - 6, false ], week.first
    assert_equal [ TODAY, true ], week.last
    assert_equal true, week[4].last
  end

  test "active_last_30 counts only the window" do
    assert_equal 2, engagement(0, 29, 30, 45).active_last_30, "today minus 29 is the oldest day inside a 30-day window"
  end

  test "streak ends today or yesterday" do
    assert_equal 3, engagement(0, 1, 2, 5).streak
    assert_equal 2, engagement(1, 2, 5).streak, "no sync yet today keeps yesterday's streak alive"
    assert_equal 0, engagement(2, 3).streak
    assert_equal 0, engagement.streak
  end

  test "last_active_on and to_h" do
    e = engagement(1, 4)
    assert_equal TODAY - 1, e.last_active_on
    h = e.to_h
    assert_equal 7, h[:week].size
    assert_equal "2026-09-22", h[:last_active_on]
    assert_equal 2, h[:active_last_30]
    assert_nil engagement.to_h[:last_active_on]
  end

  test "for loads the window from the database in the client's zone" do
    user = users(:danny)
    user.activity_days.create!(day: user.local_today)
    user.activity_days.create!(day: user.local_today - 40)
    e = Engagement.for(user)
    assert_equal 1, e.active_last_30
    assert_equal 1, e.streak
  end
end
```

`test/models/user_test.rb`: keep the existing throttle test; it still passes.

- [ ] **Step 4: Migrate, run, commit**

Run: `bin/rails db:migrate && bin/rails test test/models`
Expected: PASS.

```bash
git add db/migrate db/schema.rb app/models/activity_day.rb app/models/engagement.rb app/models/user.rb test/fixtures/activity_days.yml test/models
git commit -m "Record days active and summarize them as engagement"
```

---

## Lane T — sync and client Home (pi)

### Task T1: Sync records activity

**Files:**
- Modify: `test/controllers/api/sync_controller_test.rb`

- [ ] **Step 1: Add tests**

```ruby
  test "a successful save records today as an active day" do
    user = users(:danny)
    sign_in_as user
    put api_sync_path, params: { blob: { ciphertext: "cipher", nonce: "nonce" } }, as: :json
    assert_response :success
    assert_equal [ user.local_today ], user.activity_days.pluck(:day)
  end

  test "a rejected save records no activity" do
    user = users(:danny)
    sign_in_as user
    put api_sync_path, params: { blob: { ciphertext: "", nonce: "nonce" } }, as: :json
    assert_equal 0, user.activity_days.count
  end
```

Run: `bin/rails test test/controllers/api/sync_controller_test.rb`
Expected: PASS already (the Foundation hook is inside `touch_last_synced!`, which `save_blob` calls). No controller change is needed; commit the tests.

```bash
git add test/controllers/api/sync_controller_test.rb
git commit -m "Pin that syncing records an active day"
```

### Task T2: Layout embeds the client's summary; Home renders it

**Files:**
- Create: `app/views/shared/_activity_summary.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/javascript/controllers/navigation_controller.js`
- Modify: `app/assets/stylesheets/application.css`
- Create: `test/integration/client_activity_summary_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/integration/client_activity_summary_test.rb
require "test_helper"

class ClientActivitySummaryTest < ActionDispatch::IntegrationTest
  NAVIGATION_JS = Rails.root.join("app/javascript/controllers/navigation_controller.js")

  test "the layout embeds the logged-in client's engagement" do
    user = users(:danny)
    user.activity_days.create!(day: user.local_today)
    sign_in_as user
    get root_path

    assert_select "script#activity-summary[type='application/json']", 1
    json = JSON.parse(css_select("script#activity-summary").first.text)
    assert_equal 7, json["week"].size
    assert_equal true, json["week"].last["active"]
    assert_equal 1, json["streak"]
  end

  test "the login page embeds nothing" do
    get new_session_path
    assert_select "script#activity-summary", 0
  end

  test "the Home renderer reads the summary and explains it" do
    src = NAVIGATION_JS.read
    assert_match(/activity-summary/, src)
    assert_match(/never what you wrote/, src)
  end
end
```

- [ ] **Step 2: Implement**

```erb
<%# app/views/shared/_activity_summary.html.erb
    The client's own days-active summary for the Home screen. Same data the
    counselor sees, and nothing more. %>
<script type="application/json" id="activity-summary"><%= raw Engagement.for(current_user).to_h.to_json.gsub("</", "<\\/") %></script>
```

In `app/views/layouts/application.html.erb`, right after `<%= render "shared/practice_content" %>` add:

```erb
      <% if authenticated? %><%= render "shared/activity_summary" %><% end %>
```

In `app/javascript/controllers/navigation_controller.js`, add a method and use it in `renderHome`:

```js
  activitySummary() {
    try {
      return JSON.parse(document.getElementById("activity-summary")?.textContent || "null");
    } catch {
      return null;
    }
  }

  renderActivity() {
    const summary = this.activitySummary();
    if (!summary) return "";
    const dots = summary.week.map(({ date, active }) => {
      const initial = "SMTWTFS"[new Date(date + "T00:00:00").getDay()];
      return `<span class="act-day${active ? " active" : ""}" title="${date}">${initial}</span>`;
    }).join("");
    const streak = summary.streak ? ` · ${summary.streak} day streak` : "";
    return `
      <div class="card act-card">
        <div class="act-strip">${dots}</div>
        <p class="act-line">${summary.active_last_30} of the last 30 days${streak}</p>
        <p class="act-note">Your counselor sees this too: which days you used the app, never what you wrote.</p>
      </div>`;
  }
```

and in `renderHome()`, insert `${this.renderActivity()}` immediately after the `<p class="subtitle">What would you like to work on today?</p>` line.

Append to `app/assets/stylesheets/application.css`:

```css
.act-card{padding:12px 14px}
.act-strip{display:flex;gap:8px;justify-content:space-between;margin-bottom:8px}
.act-day{flex:1;text-align:center;font-size:11px;color:var(--lt-brown);padding:6px 0;border-radius:6px;background:var(--light-blue)}
.act-day.active{background:var(--blue);color:#fff;font-weight:600}
.act-line{font-size:13px;color:var(--deep);font-weight:600}
.act-note{font-size:11px;color:var(--lt-brown);margin-top:4px;line-height:1.4}
```

- [ ] **Step 3: Run, commit**

Run: `node --check app/javascript/controllers/navigation_controller.js && bin/rails test test/integration/client_activity_summary_test.rb test/integration`
Expected: PASS.

```bash
git add app/views/shared/_activity_summary.html.erb app/views/layouts/application.html.erb app/javascript/controllers/navigation_controller.js app/assets/stylesheets/application.css test/integration/client_activity_summary_test.rb
git commit -m "Show clients their own days-active strip on Home"
```

### Task T3: Report done

`bin/rails test && bin/rubocop`, then report commits and deviations.

---

## Lane C — dashboard (codex)

### Task C1: Strip, count, and streak on the client list

**Files:**
- Modify: `app/controllers/dashboard/clients_controller.rb`
- Modify: `app/views/dashboard/clients/index.html.erb`
- Modify: `app/assets/stylesheets/counselor.css`
- Modify: `test/controllers/dashboard/clients_controller_test.rb`

- [ ] **Step 1: Add tests**

```ruby
  test "the list shows a week strip, 30-day count, and streak per client" do
    danny = users(:danny)
    [ 0, 1, 2 ].each { |n| danny.activity_days.create!(day: danny.local_today - n) }
    sign_in_counselor_as counselors(:logan)
    get counselor_root_path

    assert_select "tr td .c-strip .c-day", 7
    assert_select "tr td .c-strip .c-day.active", 3
    assert_select "td", text: "3 of 30"
    assert_select "td", text: "3"
    assert_select "p.c-muted", /never what they wrote/
  end

  test "activity is loaded in one query however many clients" do
    logan = counselors(:logan)
    5.times do |i|
      logan.clients.create!(email_address: "c#{i}@example.com", password: NEW_AUTH_HASH,
        password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY,
        invite_code: InviteCode.generate(nil, counselor: logan))
    end
    sign_in_counselor_as logan

    queries = []
    counter = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql] =~ /activity_days/ }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get counselor_root_path }

    assert_response :success
    assert_equal 1, queries.size, queries.join("\n")
  end
```

- [ ] **Step 2: Implement**

In `Dashboard::ClientsController#index`, after `@practice = ...` add:

```ruby
    # One query for every listed client's activity; Engagement does the rest
    # in memory. Only the active list gets a strip.
    since = Date.current - Engagement::WINDOW
    days_by_client = ActivityDay.where(user_id: @active.map(&:id), day: since..).group_by(&:user_id)
    @engagement = @active.index_with { |client| Engagement.for(client, days: (days_by_client[client.id] || []).map(&:day)) }
```

In the view, change the heading area to:

```erb
<h2>Clients</h2>
<p class="c-count"><%= @practice.active_client_count %> of <%= @practice.client_limit %> active this month across the practice.</p>
<p class="c-muted">You see which days each client used the app, never what they wrote.</p>
```

and the active table to:

```erb
  <table class="c-table">
    <thead><tr><th>Email</th><th>Last 7 days</th><th>Last 30</th><th>Streak</th><th>Last active</th><th></th></tr></thead>
    <tbody>
      <% @active.each do |client| %>
        <% e = @engagement[client] %>
        <tr>
          <td><%= client.email_address %><br><span class="c-muted">joined <%= client.created_at.to_date %></span></td>
          <td>
            <span class="c-strip">
              <% e.week.each do |date, active| %>
                <span class="c-day<%= ' active' if active %>" title="<%= date %>"><%= date.strftime("%a")[0] %></span>
              <% end %>
            </span>
          </td>
          <td><%= e.active_last_30 %> of 30</td>
          <td><%= e.streak %></td>
          <td><%= client.last_synced_at ? "#{time_ago_in_words(client.last_synced_at)} ago" : "never" %></td>
          <td><%= button_to "Archive", archive_counselor_client_path(client), method: :patch, class: "c-linkbtn", form_class: "c-inline" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
```

Append to `app/assets/stylesheets/counselor.css`:

```css
.c-strip{display:inline-flex;gap:3px}
.c-day{width:18px;height:18px;line-height:18px;text-align:center;font-size:10px;border-radius:4px;background:var(--light-blue);color:var(--lt-brown)}
.c-day.active{background:var(--blue);color:#fff;font-weight:600}
```

- [ ] **Step 3: Run, commit**

Run: `bin/rails test test/controllers/dashboard/clients_controller_test.rb`
Expected: PASS.

```bash
git add app/controllers/dashboard/clients_controller.rb app/views/dashboard/clients/index.html.erb app/assets/stylesheets/counselor.css test/controllers/dashboard/clients_controller_test.rb
git commit -m "Dashboard shows a week strip, 30-day count, and streak per client"
```

### Task C2: Report done

`bin/rails test && bin/rubocop`, then report.

---

## Lane P — retention (grok)

### Task P1: Prune job and schedule

**Files:**
- Create: `app/jobs/prune_activity_days_job.rb`, `test/jobs/prune_activity_days_job_test.rb`
- Modify: `config/recurring.yml`, `README.md`

- [ ] **Step 1: Write the failing test**

```ruby
# test/jobs/prune_activity_days_job_test.rb
require "test_helper"

class PruneActivityDaysJobTest < ActiveJob::TestCase
  test "deletes only rows older than the retention window" do
    user = users(:danny)
    old = user.activity_days.create!(day: Date.current - 401)
    edge = user.activity_days.create!(day: Date.current - 400)
    recent = user.activity_days.create!(day: Date.current)

    PruneActivityDaysJob.perform_now

    assert_nil ActivityDay.find_by(id: old.id)
    assert ActivityDay.exists?(edge.id)
    assert ActivityDay.exists?(recent.id)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
# app/jobs/prune_activity_days_job.rb
#
# Days active are kept a little over a year: long enough for any summary we
# show, short enough that the table never grows without bound.
class PruneActivityDaysJob < ApplicationJob
  RETENTION = 400.days

  def perform
    ActivityDay.where(day: ...(Date.current - RETENTION.in_days.to_i)).delete_all
  end
end
```

Add to the `production:` section of `config/recurring.yml`:

```yaml
  prune_activity_days:
    class: PruneActivityDaysJob
    queue: default
    schedule: at 4am every day
```

In `README.md`, under the practices section, add one paragraph: "Each successful sync records that the client used the app that day (`activity_days`), nothing more. Rows older than 400 days are pruned daily by `PruneActivityDaysJob`."

- [ ] **Step 3: Run, commit**

Run: `bin/rails test test/jobs/prune_activity_days_job_test.rb`
Expected: PASS.

```bash
git add app/jobs/prune_activity_days_job.rb test/jobs/prune_activity_days_job_test.rb config/recurring.yml README.md
git commit -m "Prune days-active rows after 400 days"
```

### Task P2: Report done

`bin/rails test && bin/rubocop`, then report.

---

## Integration (driver)

1. Wait for the lanes; `git status` clean.
2. `bin/ci` green.
3. Manual, against a test-env server on a private DB (see the multi-tenancy plan): as a client on `localhost`, save an entry, reload Home and see today's dot and "1 of the last 30 days · 1 day streak"; as the counselor on the practice subdomain, see the same strip on the client list.
4. Push; PR #47 description gains a "3. Engagement" section.
