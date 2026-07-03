require "test_helper"

class Admin::InvitesControllerTest < ActionDispatch::IntegrationTest
  test "denies access when no admin password is configured" do
    with_admin_password(nil) do
      get admin_invites_path, headers: basic_auth("admin", "changeme")
      assert_response :unauthorized
    end
  end

  test "denies access with wrong password" do
    with_admin_password("correct-password") do
      get admin_invites_path, headers: basic_auth("admin", "wrong")
      assert_response :unauthorized
    end
  end

  test "allows access with correct password" do
    with_admin_password("correct-password") do
      get admin_invites_path, headers: basic_auth("admin", "correct-password")
      assert_response :success
    end
  end

  private

  def basic_auth(user, password)
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
  end

  def with_admin_password(value)
    creds = Rails.application.credentials
    creds.define_singleton_method(:dig) do |*keys|
      keys == [ :admin, :password ] ? value : config.dig(*keys)
    end
    yield
  ensure
    creds.singleton_class.remove_method(:dig)
  end
end
