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

  test "accepting a member invite and removing a member enqueue a seat sync" do
    invite = CounselorInvite.create!(email_address: "new@lakeside.example", role: "member", practice: practices(:lakeside), invited_by: counselors(:lee))
    assert_enqueued_with(job: StripeSeatSyncJob, args: [ practices(:lakeside).id ]) do
      post counselor_setup_path(invite.token), params: { name: "New", password: "long enough password" }
    end
    member = Counselor.find_by(email_address: "new@lakeside.example")
    sign_in_counselor_as counselors(:lee)
    assert_enqueued_with(job: StripeSeatSyncJob, args: [ practices(:lakeside).id ]) do
      delete counselor_member_path(member)
    end
  end

  test "the members page says what the next seat costs" do
    sign_in_counselor_as counselors(:lee)
    get counselor_members_path
    assert_match(/Adding a counselor adds \$50\/month/, response.body)
  end
end
