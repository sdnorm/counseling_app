# test/controllers/dashboard/passwords_controller_test.rb
require "test_helper"

class Dashboard::PasswordsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "requesting a reset emails a link on the practice host" do
    assert_enqueued_emails 1 do
      post counselor_passwords_path, params: { email_address: counselors(:logan).email_address }
    end
    assert_redirected_to new_counselor_session_path
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_match %r{https://app\.crossroadcounselor\.com/counselor/passwords/.+/edit}, mail.text_part.body.to_s
  end

  test "unknown emails get the same response and no mail" do
    assert_no_enqueued_emails do
      post counselor_passwords_path, params: { email_address: "nobody@example.com" }
    end
    assert_redirected_to new_counselor_session_path
  end

  test "resetting sets the password, revokes sessions, and redirects to login" do
    counselor = counselors(:logan)
    sign_in_counselor_as counselor
    token = counselor.password_reset_token

    patch counselor_password_path(token), params: { password: "brand new password 1", password_confirmation: "brand new password 1" }

    assert_redirected_to new_counselor_session_path
    assert_equal 0, counselor.sessions.count
    assert Counselor.authenticate_by(email_address: counselor.email_address, password: "brand new password 1")
  end

  test "short or mismatched passwords are rejected" do
    counselor = counselors(:logan)
    token = counselor.password_reset_token
    digest = counselor.password_digest

    patch counselor_password_path(token), params: { password: "short", password_confirmation: "short" }
    assert_redirected_to edit_counselor_password_path(token)
    patch counselor_password_path(token), params: { password: "long enough password", password_confirmation: "different password!" }
    assert_redirected_to edit_counselor_password_path(token)
    assert_equal digest, counselor.reload.password_digest
  end

  test "a bad token is refused" do
    get edit_counselor_password_path("bogus")
    assert_redirected_to new_counselor_password_path
  end
end
