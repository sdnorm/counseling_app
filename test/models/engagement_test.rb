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
