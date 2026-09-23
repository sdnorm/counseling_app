require "test_helper"

class Api::AccountKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:danny)
    sign_in_as @user
  end

  test "show returns both wrapped keys" do
    get api_account_keys_path, headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal @user.password_wrapped_key, response.parsed_body["password_wrapped_key"]
    assert_equal @user.recovery_wrapped_key, response.parsed_body["recovery_wrapped_key"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "changing the password swaps the auth hash and the password-wrapped key" do
    put api_account_keys_path, params: {
      current_password: AUTH_HASH, password: NEW_AUTH_HASH, password_wrapped_key: '{"nonce":"x","ciphertext":"y"}'
    }, as: :json

    assert_response :success
    @user.reload
    assert User.authenticate_by(email_address: @user.email_address, password: NEW_AUTH_HASH)
    assert_equal '{"nonce":"x","ciphertext":"y"}', @user.password_wrapped_key
  end

  test "changing the password ends every other session but keeps this one" do
    other = @user.sessions.create!(user_agent: "other", ip_address: "10.0.0.1")

    put api_account_keys_path, params: {
      current_password: AUTH_HASH, password: NEW_AUTH_HASH, password_wrapped_key: WRAPPED_KEY
    }, as: :json

    assert_response :success
    assert_nil Session.find_by(id: other.id)
    get screen_path("journal")
    assert_response :success, "the session that changed the password must survive"
  end

  test "rotating the recovery code replaces only the recovery-wrapped key" do
    digest_before = @user.password_digest

    put api_account_keys_path, params: {
      current_password: AUTH_HASH, recovery_wrapped_key: '{"nonce":"r","ciphertext":"s"}'
    }, as: :json

    assert_response :success
    @user.reload
    assert_equal '{"nonce":"r","ciphertext":"s"}', @user.recovery_wrapped_key
    assert_equal digest_before, @user.password_digest
    assert_equal 1, @user.sessions.count
  end

  test "a wrong current password changes nothing" do
    digest_before = @user.password_digest

    put api_account_keys_path, params: {
      current_password: NEW_AUTH_HASH, password: NEW_AUTH_HASH, password_wrapped_key: WRAPPED_KEY
    }, as: :json

    assert_response :unauthorized
    assert_equal [ "Incorrect password" ], response.parsed_body["errors"]
    assert_equal digest_before, @user.reload.password_digest
  end

  test "a raw password is rejected as a new password" do
    put api_account_keys_path, params: {
      current_password: AUTH_HASH, password: "correct horse battery", password_wrapped_key: WRAPPED_KEY
    }, as: :json

    assert_response :unprocessable_entity
    assert_match(/JavaScript/, response.parsed_body["errors"].join)
  end

  test "a request that changes nothing is rejected" do
    put api_account_keys_path, params: { current_password: AUTH_HASH }, as: :json
    assert_response :unprocessable_entity
  end

  test "requires authentication" do
    delete session_path
    put api_account_keys_path, params: { current_password: AUTH_HASH, recovery_wrapped_key: WRAPPED_KEY }, as: :json
    assert_response :unauthorized
  end
end
