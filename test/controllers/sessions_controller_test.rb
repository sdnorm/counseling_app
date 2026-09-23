require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "JSON login returns the account and the password-wrapped data key" do
    user = users(:danny)

    post session_path, params: { email_address: user.email_address, password: AUTH_HASH }, as: :json

    assert_response :success
    assert_equal user.id, response.parsed_body["account"]
    assert_equal user.password_wrapped_key, response.parsed_body["password_wrapped_key"]
    assert_nil response.parsed_body["recovery_wrapped_key"],
      "login must not hand out the recovery-wrapped copy"
  end

  test "JSON login with a wrong auth hash is 401 with an error" do
    post session_path, params: { email_address: users(:danny).email_address, password: NEW_AUTH_HASH }, as: :json

    assert_response :unauthorized
    assert_equal [ "Try another email address or password." ], response.parsed_body["errors"]
  end

  test "JSON login sets the session cookie" do
    user = users(:danny)
    post session_path, params: { email_address: user.email_address, password: AUTH_HASH }, as: :json

    get screen_path("journal")
    assert_response :success
  end

  test "HTML login still redirects" do
    user = users(:danny)
    post session_path, params: { email_address: user.email_address, password: AUTH_HASH }
    assert_redirected_to root_url

    delete session_path
    post session_path, params: { email_address: user.email_address, password: "wrong" }
    assert_redirected_to new_session_path
  end
end
