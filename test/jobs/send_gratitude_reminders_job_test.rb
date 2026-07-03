require "test_helper"

class SendGratitudeRemindersJobTest < ActiveSupport::TestCase
  setup do
    # danny has a push subscription fixture; give him a reminder at 09:00 Chicago time.
    @user = users(:danny)
    @user.update!(reminder_time: "09:00", time_zone: "America/Chicago", last_reminded_on: nil)
  end

  # 2026-07-02 15:00 UTC == 10:00 in Chicago (CDT, UTC-5): past the 09:00 reminder.
  PAST_REMINDER_UTC = Time.utc(2026, 7, 2, 15, 0)
  # 2026-07-02 13:00 UTC == 08:00 in Chicago: before the 09:00 reminder.
  BEFORE_REMINDER_UTC = Time.utc(2026, 7, 2, 13, 0)

  test "notifies a due user and stamps last_reminded_on with their local date" do
    notified = perform_at(PAST_REMINDER_UTC)
    assert_equal [ @user ], notified
    assert_equal Date.new(2026, 7, 2), @user.reload.last_reminded_on
  end

  test "skips a user whose local time is before their reminder time" do
    notified = perform_at(BEFORE_REMINDER_UTC)
    assert_empty notified
    assert_nil @user.reload.last_reminded_on
  end

  test "skips a user already reminded today (their local date)" do
    @user.update!(last_reminded_on: Date.new(2026, 7, 2))
    notified = perform_at(PAST_REMINDER_UTC)
    assert_empty notified
  end

  test "notifies again on the next local day" do
    @user.update!(last_reminded_on: Date.new(2026, 7, 1))
    notified = perform_at(PAST_REMINDER_UTC)
    assert_equal [ @user ], notified
  end

  test "skips users without push subscriptions" do
    users(:maria).update!(reminder_time: "09:00", time_zone: "America/Chicago")
    notified = perform_at(PAST_REMINDER_UTC)
    assert_not_includes notified, users(:maria)
  end

  test "skips users without a reminder time" do
    @user.update!(reminder_time: nil)
    notified = perform_at(PAST_REMINDER_UTC)
    assert_empty notified
  end

  test "one user's transport failure does not block other users" do
    maria = users(:maria)
    maria.update!(reminder_time: "09:00", time_zone: "America/Chicago")
    maria.push_subscriptions.create!(endpoint: "https://push.example.com/subs/maria", p256dh: "mk", auth: "ma")

    danny_endpoint = push_subscriptions(:danny_sub).endpoint
    sent_endpoints = []
    fake_send = ->(**kwargs) {
      raise SocketError, "unreachable" if kwargs[:endpoint] == danny_endpoint
      sent_endpoints << kwargs[:endpoint]
    }

    travel_to(PAST_REMINDER_UTC) do
      WebPush.stub(:payload_send, fake_send) do
        SendGratitudeRemindersJob.perform_now
      end
    end

    assert_includes sent_endpoints, "https://push.example.com/subs/maria"
    assert_equal Date.new(2026, 7, 2), maria.reload.last_reminded_on
    assert_nil users(:danny).reload.last_reminded_on, "failed user should not be stamped (will retry next run)"
  end

  test "respects the user's time zone" do
    # 15:00 UTC is 08:00 in Los Angeles (PDT, UTC-7) — not yet due there.
    @user.update!(time_zone: "America/Los_Angeles")
    notified = perform_at(PAST_REMINDER_UTC)
    assert_empty notified
  end

  private

  # Stubs at the HTTP boundary (WebPush.payload_send) so the job exercises the real
  # notify_via_push → deliver path. Returns the users whose subscriptions were pushed.
  def perform_at(utc_time)
    sent_endpoints = []
    fake_send = ->(**kwargs) { sent_endpoints << kwargs[:endpoint] }
    travel_to(utc_time) do
      WebPush.stub(:payload_send, fake_send) do
        SendGratitudeRemindersJob.perform_now
      end
    end
    sent_endpoints.filter_map { |endpoint| PushSubscription.find_by(endpoint: endpoint)&.user }.uniq
  end
end
