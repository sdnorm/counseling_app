# test/controllers/dashboard/clients_controller_test.rb
require "test_helper"

class Dashboard::ClientsControllerTest < ActionDispatch::IntegrationTest
  test "requires a counselor login" do
    get counselor_root_path
    assert_redirected_to new_counselor_session_path
  end

  test "lists only the counselor's own clients with last-active and the practice count" do
    users(:danny).update_columns(last_synced_at: 2.days.ago)
    sign_in_counselor_as counselors(:logan)
    get counselor_root_path

    assert_response :success
    assert_select "td", text: "danny@example.com"
    assert_select "td", text: "maria@example.com", count: 0
    assert_select "td", text: "2 days ago"
    assert_select ".c-count", /2 of 60 active this month/
  end

  test "archive hides the client from the active list and reactivate restores them" do
    sign_in_counselor_as counselors(:logan)
    patch archive_counselor_client_path(users(:danny))
    assert_redirected_to counselor_root_path
    assert users(:danny).reload.archived?

    get counselor_root_path
    assert_select "details.c-archived td", text: "danny@example.com"

    patch unarchive_counselor_client_path(users(:danny))
    assert_not users(:danny).reload.archived?
  end

  test "a counselor cannot archive another counselor's client" do
    sign_in_counselor_as counselors(:logan)
    patch archive_counselor_client_path(users(:maria))
    assert_response :not_found
    assert_not users(:maria).reload.archived?
  end
end
