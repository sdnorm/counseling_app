require "test_helper"

# A stale PWA cache once made a client report a fix as missing when it had
# shipped. The Settings screen shows the deployed commit so we can tell what
# build a phone is actually running.
class AppRevisionTest < ActionDispatch::IntegrationTest
  test "the revision is a short sha or unknown" do
    assert_match(/\A(\h{7}|unknown)\z/, Rails.application.config.app_revision)
  end

  test "settings shows the app version" do
    sign_in_as users(:danny)
    get screen_path("settings")
    assert_response :success
    assert_select "#app-version", text: Rails.application.config.app_revision
  end
end
