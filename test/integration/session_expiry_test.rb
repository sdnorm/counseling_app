require "test_helper"

class SessionExpiryTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:danny)
  end

  test "a fresh session stays signed in" do
    sign_in_as @user
    get root_path
    assert_response :success
  end

  test "a session older than the maximum age no longer authenticates" do
    sign_in_as @user
    session_record = @user.sessions.order(:created_at).last

    session_record.update_columns(created_at: Session::MAX_AGE.ago - 1.day)

    get root_path
    assert_redirected_to new_session_path
  end

  test "a session just inside the maximum age still authenticates" do
    sign_in_as @user
    session_record = @user.sessions.order(:created_at).last

    session_record.update_columns(created_at: Session::MAX_AGE.ago + 1.hour)

    get root_path
    assert_response :success
  end

  test "expired sessions are excluded from the active scope" do
    fresh = @user.sessions.create!(user_agent: "t", ip_address: "127.0.0.1")
    stale = @user.sessions.create!(user_agent: "t", ip_address: "127.0.0.1")
    stale.update_columns(created_at: Session::MAX_AGE.ago - 1.second)

    assert_includes Session.active, fresh
    assert_not_includes Session.active, stale
  end
end
