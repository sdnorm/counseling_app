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
