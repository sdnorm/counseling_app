require "test_helper"

class PushNotifierTest < ActiveSupport::TestCase
  setup do
    @user = users(:danny)
    @subscription = push_subscriptions(:danny_sub)
  end

  test "sends a JSON payload to each subscription" do
    @user.push_subscriptions.create!(endpoint: "https://push.example.com/subs/danny2", p256dh: "k2", auth: "a2")

    sent = []
    fake_send = ->(**kwargs) { sent << kwargs }

    WebPush.stub(:payload_send, fake_send) do
      PushNotifier.notify(@user, title: "Gratitude time", body: "Take a moment.")
    end

    assert_equal 2, sent.size
    first = sent.find { |kwargs| kwargs[:endpoint] == @subscription.endpoint }
    assert_equal @subscription.p256dh, first[:p256dh]
    assert_equal @subscription.auth, first[:auth]
    assert_equal({ "title" => "Gratitude time", "body" => "Take a moment." }, JSON.parse(first[:message]))
    assert first[:vapid].key?(:public_key)
    assert first[:vapid].key?(:private_key)
    assert_equal "mailto:spencernorman@hey.com", first[:vapid][:subject]
  end

  test "destroys subscription on ExpiredSubscription (410)" do
    raise_expired = ->(**) { raise expired_error }

    WebPush.stub(:payload_send, raise_expired) do
      assert_difference -> { PushSubscription.count }, -1 do
        PushNotifier.notify(@user, title: "t", body: "b")
      end
    end
    assert_not PushSubscription.exists?(@subscription.id)
  end

  test "destroys subscription on InvalidSubscription (404)" do
    raise_invalid = ->(**) { raise invalid_error }

    WebPush.stub(:payload_send, raise_invalid) do
      assert_difference -> { PushSubscription.count }, -1 do
        PushNotifier.notify(@user, title: "t", body: "b")
      end
    end
  end

  test "logs and continues on other response errors" do
    @user.push_subscriptions.create!(endpoint: "https://push.example.com/subs/danny2", p256dh: "k2", auth: "a2")

    calls = 0
    raise_server_error = ->(**) { calls += 1; raise generic_error }

    WebPush.stub(:payload_send, raise_server_error) do
      assert_no_difference -> { PushSubscription.count } do
        PushNotifier.notify(@user, title: "t", body: "b")
      end
    end
    assert_equal 2, calls, "should attempt every subscription despite errors"
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
