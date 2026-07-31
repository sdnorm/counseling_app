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

  test "creates an invite and emails the code" do
    with_admin_password("correct-password") do
      assert_difference -> { InviteCode.count }, 1 do
        assert_emails 1 do
          post admin_invites_path,
            params: { invite: { email_address: "Client@Example.com " } },
            headers: basic_auth("admin", "correct-password")
        end
      end
    end

    assert_redirected_to admin_invites_path
    assert_equal "client@example.com", InviteCode.last.email_address
    assert_equal [ "client@example.com" ], ActionMailer::Base.deliveries.last.to
  end

  test "rejects a blank email address" do
    with_admin_password("correct-password") do
      assert_no_difference -> { InviteCode.count } do
        assert_emails 0 do
          post admin_invites_path,
            params: { invite: { email_address: "  " } },
            headers: basic_auth("admin", "correct-password")
        end
      end
    end

    assert_redirected_to admin_invites_path
  end

  test "invite email links to signup with the code prefilled" do
    with_admin_password("correct-password") do
      post admin_invites_path,
        params: { invite: { email_address: "client@example.com" } },
        headers: basic_auth("admin", "correct-password")
    end

    code = InviteCode.last
    email = ActionMailer::Base.deliveries.last
    email.body.parts.each do |part|
      assert_includes part.body.to_s, "/users/new?code=#{code.code}",
        "expected the #{part.content_type} part to link to signup with the code"
    end
  end

  test "index shows a shareable signup link for available codes only" do
    available = InviteCode.generate("waiting@example.com")
    used = InviteCode.generate("done@example.com")
    InviteCode.claim(used.code)

    with_admin_password("correct-password") do
      get admin_invites_path, headers: basic_auth("admin", "correct-password")
    end

    assert_response :success
    assert_includes response.body, "/users/new?code=#{available.code}"
    assert_not_includes response.body, "/users/new?code=#{used.code}"
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
