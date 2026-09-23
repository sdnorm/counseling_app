require "test_helper"

class ClientActivitySummaryTest < ActionDispatch::IntegrationTest
  NAVIGATION_JS = Rails.root.join("app/javascript/controllers/navigation_controller.js")

  test "the layout embeds the logged-in client's engagement" do
    user = users(:danny)
    user.activity_days.create!(day: user.local_today)
    sign_in_as user
    get root_path

    assert_select "script#activity-summary[type='application/json']", 1
    json = JSON.parse(css_select("script#activity-summary").first.text)
    assert_equal 7, json["week"].size
    assert_equal true, json["week"].last["active"]
    assert_equal 1, json["streak"]
  end

  test "the login page embeds nothing" do
    get new_session_path
    assert_select "script#activity-summary", 0
  end

  test "the Home renderer reads the summary and explains it" do
    src = NAVIGATION_JS.read
    assert_match(/activity-summary/, src)
    assert_match(/never what you wrote/, src)
  end
end
