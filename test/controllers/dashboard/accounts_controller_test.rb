# test/controllers/dashboard/accounts_controller_test.rb
require "test_helper"

class Dashboard::AccountsControllerTest < ActionDispatch::IntegrationTest
  test "changes name and password with the current password" do
    sign_in_counselor_as counselors(:jo)
    patch counselor_account_path, params: { account: { name: "Jo B.", current_password: COUNSELOR_PASSWORD, password: "a whole new password", password_confirmation: "a whole new password" } }
    assert_redirected_to edit_counselor_account_path
    counselor = counselors(:jo).reload
    assert_equal "Jo B.", counselor.name
    assert counselor.authenticate("a whole new password")
  end

  test "wrong current password changes nothing" do
    sign_in_counselor_as counselors(:jo)
    patch counselor_account_path, params: { account: { name: "Jo B.", current_password: "wrong", password: "a whole new password", password_confirmation: "a whole new password" } }
    assert_response :unprocessable_entity
    assert_equal "Jo", counselors(:jo).reload.name
  end

  test "name alone can change without a password" do
    sign_in_counselor_as counselors(:jo)
    patch counselor_account_path, params: { account: { name: "Jo B." } }
    assert_redirected_to edit_counselor_account_path
    assert_equal "Jo B.", counselors(:jo).reload.name
  end
end
