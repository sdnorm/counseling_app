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

  test "deliver sends a JSON payload with VAPID credentials" do
    subscription = push_subscriptions(:danny_sub)

    sent = []
    fake_send = ->(**kwargs) { sent << kwargs }

    WebPush.stub(:payload_send, fake_send) do
      subscription.deliver(title: "Gratitude time", body: "Take a moment.")
    end

    assert_equal 1, sent.size
    call = sent.first
    assert_equal subscription.endpoint, call[:endpoint]
    assert_equal subscription.p256dh, call[:p256dh]
    assert_equal subscription.auth, call[:auth]
    assert_equal({ "title" => "Gratitude time", "body" => "Take a moment." }, JSON.parse(call[:message]))
    assert call[:vapid].key?(:public_key)
    assert call[:vapid].key?(:private_key)
    assert_equal "mailto:spencernorman@hey.com", call[:vapid][:subject]
  end

  test "deliver destroys itself on ExpiredSubscription (410)" do
    subscription = push_subscriptions(:danny_sub)
    raise_expired = ->(**) { raise expired_error }

    WebPush.stub(:payload_send, raise_expired) do
      subscription.deliver(title: "t", body: "b")
    end
    assert_not PushSubscription.exists?(subscription.id)
  end

  test "deliver destroys itself on InvalidSubscription (404)" do
    subscription = push_subscriptions(:danny_sub)
    raise_invalid = ->(**) { raise invalid_error }

    WebPush.stub(:payload_send, raise_invalid) do
      subscription.deliver(title: "t", body: "b")
    end
    assert_not PushSubscription.exists?(subscription.id)
  end

  test "deliver logs and survives other response errors" do
    subscription = push_subscriptions(:danny_sub)
    raise_server_error = ->(**) { raise generic_error }

    WebPush.stub(:payload_send, raise_server_error) do
      subscription.deliver(title: "t", body: "b")
    end
    assert PushSubscription.exists?(subscription.id)
  end

  private

  FakeResponse = Struct.new(:code, :message, :body)

  def expired_error
    WebPush::ExpiredSubscription.new(FakeResponse.new("410", "Gone", ""), "push.example.com")
  end

  def invalid_error
    WebPush::InvalidSubscription.new(FakeResponse.new("404", "Not Found", ""), "push.example.com")
  end

  def generic_error
    WebPush::ResponseError.new(FakeResponse.new("500", "Server Error", ""), "push.example.com")
  end
end
