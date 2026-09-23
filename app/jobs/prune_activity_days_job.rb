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
