# test/controllers/dashboard/members_controller_test.rb
require "test_helper"

class Dashboard::MembersControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "members cannot manage members" do
    sign_in_counselor_as counselors(:jo)
    get counselor_members_path
    assert_redirected_to counselor_root_path
  end

  test "owner sees members and pending invites" do
    CounselorInvite.create!(email_address: "pending@example.com", role: "member", practice: practices(:crossroads), invited_by: counselors(:logan))
    sign_in_counselor_as counselors(:logan)
    get counselor_members_path
    assert_select "td", text: "Jo"
    assert_select "td", text: "pending@example.com"
  end

  test "owner invites a member by email" do
    sign_in_counselor_as counselors(:logan)
    assert_enqueued_emails 1 do
      assert_difference -> { CounselorInvite.count }, 1 do
        post counselor_members_path, params: { member: { email_address: "new@example.com" } }
      end
    end
    invite = CounselorInvite.last
    assert_equal practices(:crossroads), invite.practice
    assert_equal "member", invite.role
    assert_equal counselors(:logan), invite.invited_by
  end

  test "owner removes a member but not themselves" do
    sign_in_counselor_as counselors(:logan)
    delete counselor_member_path(counselors(:jo))
    assert counselors(:jo).reload.removed?

    delete counselor_member_path(counselors(:logan))
    assert_not counselors(:logan).reload.removed?
    assert_redirected_to counselor_members_path
  end

  test "owner cannot remove someone from another practice" do
    sign_in_counselor_as counselors(:logan)
    delete counselor_member_path(counselors(:sam))
    assert_response :not_found
  end
end
