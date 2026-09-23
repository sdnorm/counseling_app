require "test_helper"

# The client screens render the counselor's links from a JSON blob the
# layout embeds. There is no JS harness, so pin both halves statically.
class ClientPracticeContentTest < ActionDispatch::IntegrationTest
  RESOURCES_JS = Rails.root.join("app/javascript/controllers/resources_controller.js")
  NAVIGATION_JS = Rails.root.join("app/javascript/controllers/navigation_controller.js")

  test "the layout embeds the client's practice content" do
    practices(:crossroads).resource_links.create!(title: "Crossroads Site", url: "https://crossroadcounselor.com/", description: "About")
    sign_in_as users(:danny)
    get root_path

    assert_select "script#practice-content[type='application/json']", 1
    json = JSON.parse(css_select("script#practice-content").first.text)
    assert_equal "Crossroads Site", json["resources"].first["title"]
    assert_equal "(225) 341-4147", json["schedule"]["phone"]
  end

  test "no counselor content is hardcoded in the client JavaScript" do
    [ RESOURCES_JS, NAVIGATION_JS ].each do |path|
      assert_no_match(/crossroad|therapyportal|225\) 341|logan@/i, path.read, "#{path.basename} still hardcodes Crossroads content")
    end
    assert_match(/practice-content/, RESOURCES_JS.read)
    assert_match(/practice-content/, NAVIGATION_JS.read)
  end
end
