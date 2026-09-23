# test/controllers/dashboard/sessions_controller_test.rb
require "test_helper"

class Dashboard::SessionsControllerTest < ActionDispatch::IntegrationTest
  test "login page renders on any host with that host's brand" do
    host! "app.crossroadcounselor.com"
    get new_counselor_session_path
    assert_response :success
    assert_select "title", /Crossroads/
  end

  test "valid login starts a counselor session and lands on the dashboard" do
    sign_in_counselor_as counselors(:logan)
    assert_redirected_to counselor_root_path
    get counselor_root_path
    assert_response :success
    assert cookies[:counselor_session_id].present?
    assert_nil cookies[:session_id], "counselor login must not create a client session"
  end

  test "wrong password is rejected" do
    sign_in_counselor_as counselors(:logan), password: "nope nope nope"
    assert_redirected_to new_counselor_session_path
    get counselor_root_path
    assert_redirected_to new_counselor_session_path
  end

  test "a removed counselor cannot log in and an existing session dies" do
    sign_in_counselor_as counselors(:jo)
    counselors(:jo).remove!
    get counselor_root_path
    assert_redirected_to new_counselor_session_path

    sign_in_counselor_as counselors(:jo)
    assert_redirected_to new_counselor_session_path
  end

  test "logout ends the session" do
    sign_in_counselor_as counselors(:logan)
    delete counselor_session_path
    assert_response :see_other
    get counselor_root_path
    assert_redirected_to new_counselor_session_path
  end

  test "dashboard pages are never cached" do
    sign_in_counselor_as counselors(:logan)
    get counselor_root_path
    assert_match(/no-store/, response.headers["Cache-Control"])
  end
end
