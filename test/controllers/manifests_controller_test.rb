require "test_helper"

class ManifestsControllerTest < ActionDispatch::IntegrationTest
  test "generic manifest on the product host" do
    host! "example.com"
    get manifest_path

    assert_response :success
    assert_equal "application/manifest+json", response.media_type
    body = JSON.parse(response.body)
    assert_equal "Counseling App", body["name"]
    assert_equal "#32b1c3", body["theme_color"]
    assert_match %r{/assets/generic/icon-192}, body["icons"].first["src"]
    assert_match(/public/, response.headers["Cache-Control"])
  end

  test "practice manifest on a custom domain uses its name, colors, and icon" do
    practice = practices(:crossroads)
    practice.icon.attach(png_upload(512))
    practice.save!
    host! "app.crossroadcounselor.com"

    get manifest_path

    body = JSON.parse(response.body)
    assert_equal "Crossroads Professional Counseling", body["name"]
    assert_equal "Crossroads Professional Counseling", body["short_name"]
    assert_match %r{/rails/active_storage/representations/proxy/}, body["icons"].first["src"]
    assert_equal [ "192x192", "512x512" ], body["icons"].map { |i| i["sizes"] }
  end

  test "practice without an icon falls back to the generic icons" do
    host! "riverbend.example.com"
    get manifest_path
    body = JSON.parse(response.body)
    assert_equal "Riverbend Therapy", body["name"]
    assert_match %r{/assets/generic/icon-512}, body["icons"].last["src"]
  end

  test "manifest is public" do
    get manifest_path
    assert_response :success
  end
end
