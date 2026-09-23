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
