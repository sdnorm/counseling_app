require "test_helper"

class PushSubscriptionTest < ActiveSupport::TestCase
  test "valid with endpoint, p256dh, and auth" do
    sub = users(:danny).push_subscriptions.new(
      endpoint: "https://push.example.com/subs/new",
      p256dh: "key",
      auth: "secret"
    )
    assert sub.valid?
  end

  test "requires endpoint, p256dh, and auth" do
    sub = users(:danny).push_subscriptions.new
    assert_not sub.valid?
    assert_includes sub.errors[:endpoint], "can't be blank"
    assert_includes sub.errors[:p256dh], "can't be blank"
    assert_includes sub.errors[:auth], "can't be blank"
  end
end
