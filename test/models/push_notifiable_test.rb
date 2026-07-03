require "test_helper"

class PushNotifiableTest < ActiveSupport::TestCase
  setup do
    @user = users(:danny)
  end

  test "notify_via_push delivers to each subscription" do
    @user.push_subscriptions.create!(endpoint: "https://push.example.com/subs/danny2", p256dh: "k2", auth: "a2")

    sent = []
    fake_send = ->(**kwargs) { sent << kwargs[:endpoint] }

    WebPush.stub(:payload_send, fake_send) do
      @user.notify_via_push(title: "Gratitude time", body: "Take a moment.")
    end

    assert_equal 2, sent.size
    assert_includes sent, push_subscriptions(:danny_sub).endpoint
  end

  test "notify_via_push continues past a failing subscription" do
    @user.push_subscriptions.create!(endpoint: "https://push.example.com/subs/danny2", p256dh: "k2", auth: "a2")

    calls = 0
    response = Struct.new(:code, :message, :body).new("500", "Server Error", "")
    raise_server_error = ->(**) { calls += 1; raise WebPush::ResponseError.new(response, "push.example.com") }

    WebPush.stub(:payload_send, raise_server_error) do
      @user.notify_via_push(title: "t", body: "b")
    end

    assert_equal 2, calls, "should attempt every subscription despite errors"
    assert_equal 2, @user.push_subscriptions.count
  end

  test "notify_via_push is a no-op for a user with no subscriptions" do
    assert_nothing_raised { users(:maria).notify_via_push(title: "t", body: "b") }
  end
end
