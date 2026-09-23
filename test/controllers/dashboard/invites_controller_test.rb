# test/controllers/dashboard/invites_controller_test.rb
require "test_helper"

class Dashboard::InvitesControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup { sign_in_counselor_as counselors(:logan) }

  test "creating an invite without an email shows the link and code, sends nothing" do
    assert_no_enqueued_emails do
      assert_difference -> { counselors(:logan).invite_codes.count }, 1 do
        post counselor_invites_path, params: { invite: { email_address: "" } }
      end
    end
    code = counselors(:logan).invite_codes.order(:created_at).last
    assert_redirected_to counselor_invites_path(highlight: code.id)
    follow_redirect!
    assert_select ".c-code", text: code.code
    assert_select "input[value=?]", "https://app.crossroadcounselor.com/users/new?code=#{code.code}"
  end

  test "creating an invite with an email also sends it" do
    assert_enqueued_emails 1 do
      post counselor_invites_path, params: { invite: { email_address: "new@example.com" } }
    end
  end

  test "at the limit no code is made and the message explains" do
    practices(:crossroads).update!(client_limit_per_counselor: 1)
    users(:danny).update_columns(last_synced_at: 1.hour.ago)
    users(:maria).update_columns(last_synced_at: 1.hour.ago)

    assert_no_difference -> { InviteCode.count } do
      post counselor_invites_path, params: { invite: { email_address: "" } }
    end
    assert_response :unprocessable_entity
    assert_match(/2 active clients this month, which is your limit/, response.body)
  end

  test "the list shows status and only this counselor's codes" do
    used = InviteCode.generate("gone@example.com", counselor: counselors(:logan))
    InviteCode.claim(used.code)
    used.update!(user: users(:danny))
    InviteCode.generate(nil, counselor: counselors(:jo))

    get counselor_invites_path
    assert_select "td", text: used.code
    assert_select "td", text: /used by danny@example.com/
    assert_select "tbody tr", count: 1 + counselors(:logan).invite_codes.where(used: false).count
  end

  test "no subscription means no client invites, with role-specific copy" do
    sign_in_counselor_as counselors(:sam)
    assert_no_difference -> { InviteCode.count } do
      post counselor_invites_path, params: { invite: { email_address: "" } }
    end
    assert_response :unprocessable_entity
    assert_match(/Start your free trial/, response.body)
  end
end
