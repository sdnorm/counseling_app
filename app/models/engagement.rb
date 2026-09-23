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
