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

    put api_sync_path, params: { blob: { ciphertext: "x", nonce: "n" } }, as: :json
    assert_response :unauthorized
  end

  test "account keys api requires authentication" do
    get api_account_keys_path, headers: { "Accept" => "application/json" }
    assert_response :unauthorized

    put api_account_keys_path, params: { current_password: AUTH_HASH, recovery_wrapped_key: WRAPPED_KEY }, as: :json
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

  test "intentionally public routes stay public" do
    get new_session_path
    assert_response :success

    get new_password_path
    assert_response :success

    get new_user_path
    assert_response :success

    get "/api/push/vapid_public_key"
    assert_response :success

    # The webhook endpoint is public by design, but unsigned requests die fast.
    post stripe_webhooks_path, params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :bad_request,
      "an unsigned webhook post must be rejected, not redirected to login"
  end

  test "authenticated user can access screens and sync" do
    sign_in_as users(:danny)

    get screen_path("journal")
    assert_response :success

    get api_sync_path, headers: { "Accept" => "application/json" }
    assert_includes [ 200, 404 ], response.status  # 404 = no blob saved yet, still authenticated
  end

  COUNSELOR_PAGES = -> {
    [ counselor_root_path, counselor_invites_path, edit_counselor_practice_path,
      counselor_members_path, edit_counselor_account_path ]
  }

  test "every counselor page requires a counselor login" do
    instance_exec(&COUNSELOR_PAGES).each do |path|
      get path
      assert_redirected_to new_counselor_session_path, "expected #{path} to redirect to counselor login"
    end
    patch archive_counselor_client_path(users(:danny))
    assert_redirected_to new_counselor_session_path
    post counselor_invites_path
    assert_redirected_to new_counselor_session_path
  end

  test "a client login does not open counselor pages" do
    sign_in_as users(:danny)
    get counselor_root_path
    assert_redirected_to new_counselor_session_path
  end

  test "platform pages need a platform admin" do
    get platform_root_path
    assert_redirected_to new_counselor_session_path
    sign_in_counselor_as counselors(:sam)
    get platform_root_path
    assert_response :not_found
  end

  test "counselor login, password reset, setup, and the manifest stay public" do
    get new_counselor_session_path
    assert_response :success
    get new_counselor_password_path
    assert_response :success
    get counselor_setup_path("bogus")
    assert_response :not_found
    get manifest_path
    assert_response :success
  end
end
