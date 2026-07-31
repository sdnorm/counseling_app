require "test_helper"

class Api::PushControllerTest < ActionDispatch::IntegrationTest
  test "vapid_public_key is reachable without authentication" do
    get api_push_vapid_public_key_path
    assert_response :success
    assert response.parsed_body.key?("public_key")
  end

  test "create requires authentication" do
    post api_push_path, params: { endpoint: "https://push.example.com/subs/x", p256dh: "k", auth: "a" }, as: :json
    assert_response :unauthorized
  end

  test "create stores a new subscription" do
    sign_in_as users(:danny)
    assert_difference -> { users(:danny).push_subscriptions.count }, 1 do
      post api_push_path, params: { endpoint: "https://push.example.com/subs/new", p256dh: "k", auth: "a" }, as: :json
    end
    assert_response :success
  end

  test "create upserts by endpoint" do
    sign_in_as users(:danny)
    existing = push_subscriptions(:danny_sub)
    assert_no_difference -> { PushSubscription.count } do
      post api_push_path, params: { endpoint: existing.endpoint, p256dh: "new-key", auth: "new-secret" }, as: :json
    end
    assert_response :success
    assert_equal "new-key", existing.reload.p256dh
  end

  test "create rejects invalid params" do
    sign_in_as users(:danny)
    post api_push_path, params: { endpoint: "https://push.example.com/subs/bad", p256dh: "", auth: "" }, as: :json
    assert_response :unprocessable_entity
  end

  test "destroy removes the subscription" do
    sign_in_as users(:danny)
    assert_difference -> { PushSubscription.count }, -1 do
      delete api_push_path, params: { endpoint: push_subscriptions(:danny_sub).endpoint }, as: :json
    end
    assert_response :success
  end

  test "destroy returns not_found for unknown endpoint" do
    sign_in_as users(:danny)
    delete api_push_path, params: { endpoint: "https://push.example.com/subs/nope" }, as: :json
    assert_response :not_found
  end

  test "update_preferences stores reminder time and zone" do
    sign_in_as users(:danny)
    patch api_push_preferences_path, params: { reminder_time: "08:15", time_zone: "America/Denver" }, as: :json
    assert_response :success
    users(:danny).reload
    assert_equal "08:15", users(:danny).reminder_time
    assert_equal "America/Denver", users(:danny).time_zone
  end

  test "update_preferences rejects invalid values" do
    sign_in_as users(:danny)
    patch api_push_preferences_path, params: { reminder_time: "25:99", time_zone: "America/Chicago" }, as: :json
    assert_response :unprocessable_entity
  end

  test "update_preferences requires authentication" do
    patch api_push_preferences_path, params: { reminder_time: "08:15", time_zone: "America/Denver" }, as: :json
    assert_response :unauthorized
  end

  test "create claims an endpoint previously registered to another user" do
    existing = push_subscriptions(:danny_sub)
    sign_in_as users(:maria)

    assert_no_difference -> { PushSubscription.count } do
      post api_push_path, params: { endpoint: existing.endpoint, p256dh: "maria-key", auth: "maria-secret" }, as: :json
    end

    assert_response :success
    existing.reload
    assert_equal users(:maria), existing.user, "the device now belongs to the signed-in user"
    assert_equal "maria-key", existing.p256dh
    assert_empty users(:danny).push_subscriptions.reload,
      "previous owner must not keep a subscription to a device they no longer use"
  end

  test "destroy only removes the current user's own subscription" do
    existing = push_subscriptions(:danny_sub)
    sign_in_as users(:maria)

    assert_no_difference -> { PushSubscription.count } do
      delete api_push_path, params: { endpoint: existing.endpoint }, as: :json
    end
    assert_response :not_found
  end
end
