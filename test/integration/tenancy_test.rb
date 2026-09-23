require "test_helper"

class TenancyTest < ActionDispatch::IntegrationTest
  test "the login page on a custom domain wears that practice" do
    host! "app.crossroadcounselor.com"
    get new_session_path
    assert_select "title", "Sign in · Crossroads Professional Counseling"
    assert_select ".auth-brand .mark", text: /Crossroads/i
    assert_select "meta[name=theme-color][content='#32b1c3']"
  end

  test "the login page on a slug subdomain wears that practice, with generic colors when unset" do
    host! "riverbend.example.com"
    get new_session_path
    assert_select "title", "Sign in · Riverbend Therapy"
    assert_select "style", false, "no color override when the practice has no colors"
  end

  test "custom colors override the palette" do
    practices(:riverbend).update!(primary_color: "#112233", accent_color: "#445566")
    host! "riverbend.example.com"
    get new_session_path
    assert_select "style", /--blue:\s*#112233/
    assert_select "style", /--orange:\s*#445566/
  end

  test "the bare product host and unknown subdomains wear the generic brand" do
    [ "example.com", "nobody.example.com" ].each do |host|
      host! host
      get new_session_path
      assert_select "title", "Sign in · Counseling App"
      assert_select "link[rel=apple-touch-icon][href*='generic/apple-touch-icon']"
    end
  end

  test "a logged in client wears their own practice even on the product host" do
    host! "example.com"
    sign_in_as users(:danny)
    get root_path
    assert_select "title", "Crossroads Professional Counseling"
    assert_select "#topbar-title", text: /Crossroads/i
  end

  test "a practice logo replaces the wordmark text" do
    practice = practices(:riverbend)
    practice.logo.attach(png_upload(400, 100, name: "logo.png"))
    practice.save!
    host! "riverbend.example.com"
    get new_session_path
    assert_select ".auth-brand img[alt='Riverbend Therapy']"
  end
end
