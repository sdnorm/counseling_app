require "test_helper"

class PasswordResetSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:danny)
    @token = @user.password_reset_token
  end

  test "blank password is rejected and leaves the password unchanged" do
    digest_before = @user.password_digest

    patch password_path(@token), params: { password: "", password_confirmation: "" }

    assert_redirected_to edit_password_path(@token)
    assert_equal digest_before, @user.reload.password_digest
    assert User.authenticate_by(email_address: @user.email_address, password: "password"),
      "original password must still work since the reset did not happen"
  end

  test "missing password param is rejected rather than reported as success" do
    digest_before = @user.password_digest

    patch password_path(@token)

    assert_redirected_to edit_password_path(@token)
    assert_nil flash[:notice], "must not claim the password was reset"
    assert_equal digest_before, @user.reload.password_digest
  end

  test "blank password does not destroy existing sessions" do
    @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

    patch password_path(@token), params: { password: "", password_confirmation: "" }

    assert_equal 1, @user.sessions.count,
      "sessions must survive a reset that did not actually change the password"
  end

  test "valid password reset still works and revokes sessions" do
    @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    digest_before = @user.password_digest

    patch password_path(@token), params: { password: "newpassword123", password_confirmation: "newpassword123" }

    assert_redirected_to new_session_path
    assert_not_equal digest_before, @user.reload.password_digest
    assert_equal 0, @user.sessions.count
    assert User.authenticate_by(email_address: @user.email_address, password: "newpassword123")
  end

  test "mismatched confirmation is still rejected" do
    digest_before = @user.password_digest

    patch password_path(@token), params: { password: "newpassword123", password_confirmation: "different123" }

    assert_redirected_to edit_password_path(@token)
    assert_equal digest_before, @user.reload.password_digest
  end
end
