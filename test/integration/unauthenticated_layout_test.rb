require "test_helper"

class UnauthenticatedLayoutTest < ActionDispatch::IntegrationTest
  UNAUTHENTICATED_PAGES = {
    "sign in" => "/session/new",
    "sign up" => "/users/new",
    "password reset" => "/passwords/new"
  }.freeze

  test "every logged-out page uses the app's auth styling" do
    UNAUTHENTICATED_PAGES.each do |name, path|
      get path
      assert_response :success, "expected #{name} to render"
      assert_includes response.body, "auth-screen",
        "expected the #{name} page to use the shared auth-screen styling"
    end
  end

  test "the sign in form uses the app's button and field styling" do
    get new_session_path

    assert_includes response.body, %(class="auth-screen")
    assert_includes response.body, %(class="field")
    assert_match(/<input[^>]*type="submit"[^>]*class="[^"]*btn/, response.body)
  end

  test "logged-out pages do not render the signed-in app chrome" do
    UNAUTHENTICATED_PAGES.each do |name, path|
      get path
      assert_no_match(/class="bottom-nav"/, response.body,
        "the #{name} page must not show the signed-in navigation")
    end
  end

  test "the sign in page links to password reset and sign up" do
    get new_session_path
    assert_select "a[href=?]", new_password_path
    assert_select "a[href=?]", new_user_path
  end
end
