# test/controllers/platform/practices_controller_test.rb
require "test_helper"

class Platform::PracticesControllerTest < ActionDispatch::IntegrationTest
  test "non-admin counselors get 404" do
    sign_in_counselor_as counselors(:sam)
    get platform_root_path
    assert_response :not_found
  end

  test "anonymous is sent to counselor login" do
    get platform_root_path
    assert_redirected_to new_counselor_session_path
  end

  test "admin sees every practice with host, owner, counts, and trial" do
    users(:danny).update_columns(last_synced_at: 1.day.ago)
    sign_in_counselor_as counselors(:logan)
    get platform_root_path
    assert_response :success
    assert_select "td", text: "Crossroads Professional Counseling"
    assert_select "td", text: "app.crossroadcounselor.com"
    assert_select "td", text: "riverbend.example.com"
    assert_select "td", text: "logan@crossroadcounselor.com"
  end

  test "admin sets a custom domain" do
    sign_in_counselor_as counselors(:logan)
    patch platform_practice_path(practices(:riverbend)), params: { practice: { custom_domain: "App.Riverbend.Example" } }
    assert_redirected_to platform_practice_path(practices(:riverbend))
    assert_equal "app.riverbend.example", practices(:riverbend).reload.custom_domain
  end

  test "a duplicate custom domain is refused" do
    sign_in_counselor_as counselors(:logan)
    patch platform_practice_path(practices(:riverbend)), params: { practice: { custom_domain: "app.crossroadcounselor.com" } }
    assert_response :unprocessable_entity
  end

  test "index shows billing status and the practice page toggles complimentary" do
    sign_in_counselor_as counselors(:logan)
    get platform_root_path
    assert_select "td", text: /Active · month/i
    patch platform_practice_path(practices(:riverbend)), params: { practice: { complimentary: "1" } }
    assert practices(:riverbend).reload.complimentary?
  end
end
