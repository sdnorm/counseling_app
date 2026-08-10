require "test_helper"

class AuthenticationLockdownTest < ActionDispatch::IntegrationTest
  # Must match valid_screens in ScreensController#show
  SCREENS = %w[journal gratitude emotions coping triangle checkin takeaways agenda resources settings]

  test "root requires authentication" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "every screen requires authentication" do
    SCREENS.each do |id|
      get screen_path(id)
      assert_redirected_to new_session_path, "expected /screens/#{id} to redirect to login"
    end
  end

  test "sync api requires authentication" do
    get api_sync_path, headers: { "Accept" => "application/json" }
    assert_response :unauthorized

    put api_sync_path, params: { blob: { ciphertext: "x", nonce: "n", salt: "s" } }, as: :json
    assert_response :unauthorized

    post reset_api_sync_path, params: { password: "password" }, as: :json
    assert_response :unauthorized
  end

  test "push api requires authentication" do
    post api_push_path, params: { endpoint: "https://push.example/e" }, as: :json
    assert_response :unauthorized

    delete api_push_path, params: { endpoint: "https://push.example/e" }, as: :json
    assert_response :unauthorized

    patch "/api/push/preferences", params: { reminder_time: "09:00" }, as: :json
    assert_response :unauthorized
  end

  test "admin invites require http basic auth" do
    get admin_invites_path
    assert_response :unauthorized
  end

  test "intentionally public routes stay public" do
    get new_session_path
    assert_response :success

    get new_password_path
    assert_response :success

    get new_user_path
    assert_response :success

    get "/api/push/vapid_public_key"
    assert_response :success
  end

  test "authenticated user can access screens and sync" do
    sign_in_as users(:danny)

    get screen_path("journal")
    assert_response :success

    get api_sync_path, headers: { "Accept" => "application/json" }
    assert_includes [ 200, 404 ], response.status  # 404 = no blob saved yet, still authenticated
  end
end
