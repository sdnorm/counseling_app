require "test_helper"

class PostLoginRedirectTest < ActionDispatch::IntegrationTest
  test "an unauthenticated page is remembered as the post-login destination" do
    get screen_path("journal")
    assert_redirected_to new_session_path

    sign_in_as users(:danny)
    assert_redirected_to screen_path("journal")
  end

  # A session that lapses while the app is polling /api/sync would otherwise
  # make the API path the post-login destination: the user lands on raw JSON,
  # and that navigation is what let the service worker cache an /api response.
  test "an unauthenticated api request is not remembered as the destination" do
    get api_sync_path, headers: { "Accept" => "application/json" }
    assert_response :unauthorized

    sign_in_as users(:danny)
    assert_redirected_to root_path
  end

  test "an api request does not displace a page already remembered" do
    get screen_path("gratitude")
    assert_redirected_to new_session_path

    get api_sync_path, headers: { "Accept" => "application/json" }
    assert_response :unauthorized

    sign_in_as users(:danny)
    assert_redirected_to screen_path("gratitude"),
      "the page the user was actually trying to reach must survive a background API 401"
  end
end
