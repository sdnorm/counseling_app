require "test_helper"

class Api::SyncControllerTest < ActionDispatch::IntegrationTest
  # The client stamps its local database with this id so it can tell whether the
  # data on the device belongs to the account that is signing in.
  test "show identifies the account when a blob exists" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "c", nonce: "n", salt: "s")
    sign_in_as user

    get api_sync_path, headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal user.id, response.parsed_body["account"]
  end

  test "show identifies the account even when no blob exists yet" do
    user = users(:maria)
    sign_in_as user

    get api_sync_path, headers: { "Accept" => "application/json" }

    assert_response :not_found
    assert_equal user.id, response.parsed_body["account"],
      "a first-time user still needs to know which account the device now holds"
  end

  test "two accounts report different identifiers" do
    sign_in_as users(:danny)
    get api_sync_path, headers: { "Accept" => "application/json" }
    danny_account = response.parsed_body["account"]

    delete session_path
    sign_in_as users(:maria)
    get api_sync_path, headers: { "Accept" => "application/json" }
    maria_account = response.parsed_body["account"]

    assert_not_equal danny_account, maria_account
  end

  test "show still returns the blob material" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "cipher", nonce: "nonce", salt: "salt")
    sign_in_as user

    get api_sync_path, headers: { "Accept" => "application/json" }

    assert_equal "cipher", response.parsed_body["ciphertext"]
    assert_equal "nonce", response.parsed_body["nonce"]
    assert_equal "salt", response.parsed_body["salt"]
  end
end
