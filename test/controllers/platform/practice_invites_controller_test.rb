# test/controllers/platform/practice_invites_controller_test.rb
require "test_helper"

class Platform::PracticeInvitesControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup { sign_in_counselor_as counselors(:logan) }

  test "inviting an owner for a new practice sends the setup link and shows it" do
    assert_enqueued_emails 1 do
      assert_difference -> { CounselorInvite.count }, 1 do
        post platform_practice_invites_path, params: { practice_invite: { email_address: "pat@example.com", practice_name: "Calm Waters" } }
      end
    end
    invite = CounselorInvite.last
    assert_equal "owner", invite.role
    assert_equal "Calm Waters", invite.practice_name
    assert_nil invite.practice
    assert_redirected_to platform_practice_invite_path(invite)
    follow_redirect!
    assert_select "input[value*=?]", "/counselor/setup/#{invite.token}"
  end

  test "inviting an owner into an existing practice" do
    post platform_practice_invites_path, params: { practice_invite: { email_address: "logan2@example.com", practice_id: practices(:crossroads).id } }
    invite = CounselorInvite.last
    assert_equal practices(:crossroads), invite.practice
    assert_equal "owner", invite.role
    follow_redirect!
    assert_select "input[value*=?]", "https://app.crossroadcounselor.com/counselor/setup/"
  end

  test "both or neither target is refused" do
    assert_no_difference -> { CounselorInvite.count } do
      post platform_practice_invites_path, params: { practice_invite: { email_address: "x@example.com" } }
    end
    assert_response :unprocessable_entity
  end

  test "non-admins get 404" do
    sign_in_counselor_as counselors(:sam)
    get new_platform_practice_invite_path
    assert_response :not_found
  end
end
