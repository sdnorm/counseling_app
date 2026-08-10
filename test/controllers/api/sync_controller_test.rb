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

  # --- passphrase reset ---

  test "reset with the correct password and a blob replaces the encrypted blob" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "old", nonce: "n", salt: "s")
    sign_in_as user

    post reset_api_sync_path, params: {
      password: "password",
      blob: { ciphertext: "new", nonce: "n2", salt: "s2" }
    }, as: :json

    assert_response :success
    blob = user.reload.encrypted_blob
    assert_equal "new", blob.ciphertext
    assert_equal "s2", blob.salt
  end

  test "reset with the correct password and a blob works when no blob exists yet" do
    user = users(:maria)
    sign_in_as user

    post reset_api_sync_path, params: {
      password: "password",
      blob: { ciphertext: "new", nonce: "n2", salt: "s2" }
    }, as: :json

    assert_response :success
    assert_equal "new", user.reload.encrypted_blob.ciphertext
  end

  test "reset without a blob deletes the encrypted blob" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "old", nonce: "n", salt: "s")
    sign_in_as user

    post reset_api_sync_path, params: { password: "password" }, as: :json

    assert_response :success
    assert_nil user.reload.encrypted_blob
  end

  test "reset without a blob succeeds even when there is nothing to delete" do
    sign_in_as users(:maria)

    post reset_api_sync_path, params: { password: "password" }, as: :json

    assert_response :success
    assert response.parsed_body["success"]
  end

  test "reset with an empty blob does not wipe the existing blob" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "old", nonce: "n", salt: "s")
    sign_in_as user

    post reset_api_sync_path, params: { password: "password", blob: {} }, as: :json

    assert_operator response.status, :>=, 400
    assert_not_nil user.reload.encrypted_blob
  end

  test "reset with a wrong password changes nothing and says so" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "old", nonce: "n", salt: "s")
    sign_in_as user

    post reset_api_sync_path, params: {
      password: "wrong",
      blob: { ciphertext: "new", nonce: "n2", salt: "s2" }
    }, as: :json

    assert_response :unauthorized
    assert_equal "old", user.reload.encrypted_blob.ciphertext
    assert_includes response.parsed_body["errors"], "Incorrect password"
  end

  test "reset with a wrong password and no blob does not delete anything" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "old", nonce: "n", salt: "s")
    sign_in_as user

    post reset_api_sync_path, params: { password: "wrong" }, as: :json

    assert_response :unauthorized
    assert_not_nil user.reload.encrypted_blob
  end

  test "reset with an invalid blob is rejected without touching the old blob" do
    user = users(:danny)
    user.create_encrypted_blob!(ciphertext: "old", nonce: "n", salt: "s")
    sign_in_as user

    post reset_api_sync_path, params: {
      password: "password",
      blob: { ciphertext: "", nonce: "n2", salt: "s2" }
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "old", user.reload.encrypted_blob.ciphertext
  end

  test "api responses are never cacheable" do
    sign_in_as users(:danny)

    get api_sync_path, headers: { "Accept" => "application/json" }

    assert_equal "no-store", response.headers["Cache-Control"],
      "a cached /api/sync response could hand a fresh account another account's blob or salt"
  end
end
