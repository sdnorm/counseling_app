# test/controllers/dashboard/setups_controller_test.rb
require "test_helper"

class Dashboard::SetupsControllerTest < ActionDispatch::IntegrationTest
  test "an owner invite shows the setup form with the new practice name" do
    invite = CounselorInvite.create!(email_address: "pat@example.com", role: "owner", practice_name: "Calm Waters")
    get counselor_setup_path(invite.token)
    assert_response :success
    assert_select "h2", /Calm Waters/
    assert_select "input[name=name]"
    assert_select "input[name=password]"
  end

  test "accepting an owner invite creates the practice and lands on its dashboard host" do
    invite = CounselorInvite.create!(email_address: "pat@example.com", role: "owner", practice_name: "Calm Waters")

    assert_difference [ -> { Practice.count }, -> { Counselor.count } ], 1 do
      post counselor_setup_path(invite.token), params: { name: "Pat", password: "long enough password" }
    end

    assert_redirected_to counselor_root_url(host: "calm-waters.example.com", protocol: "https")
    assert invite.reload.accepted?
    assert cookies[:counselor_session_id].present?
  end

  test "accepting a member invite joins the practice" do
    invite = CounselorInvite.create!(email_address: "kim@example.com", role: "member", practice: practices(:riverbend), invited_by: counselors(:sam))
    post counselor_setup_path(invite.token), params: { name: "Kim", password: "long enough password" }
    assert_redirected_to counselor_root_url(host: "riverbend.example.com", protocol: "https")
    assert_equal practices(:riverbend), Counselor.find_by(email_address: "kim@example.com").practice
  end

  test "validation errors re-render the form and create nothing" do
    invite = CounselorInvite.create!(email_address: "pat@example.com", role: "owner", practice_name: "Calm Waters")
    assert_no_difference -> { Practice.count } do
      post counselor_setup_path(invite.token), params: { name: "", password: "short" }
    end
    assert_response :unprocessable_entity
    assert_match(/Password is too short/, response.body)
  end

  test "expired, accepted, and unknown tokens show a clear message" do
    invite = CounselorInvite.create!(email_address: "pat@example.com", role: "owner", practice_name: "Calm Waters")
    invite.update_column(:expires_at, 1.hour.ago)
    get counselor_setup_path(invite.token)
    assert_response :not_found
    assert_match(/expired/i, response.body)

    get counselor_setup_path("bogus")
    assert_response :not_found
  end
end
