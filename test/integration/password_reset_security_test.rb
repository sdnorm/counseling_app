require "test_helper"

class PasswordResetSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:danny)
    @token = @user.password_reset_token
    @keys = { password: NEW_AUTH_HASH, password_wrapped_key: '{"nonce":"p","ciphertext":"q"}',
              recovery_wrapped_key: '{"nonce":"r","ciphertext":"s"}' }
  end

  test "edit renders the material the browser needs" do
    get edit_password_path(@token)

    assert_response :success
    assert_includes response.body, ERB::Util.html_escape(@user.recovery_wrapped_key),
      "the reset page must carry the recovery-wrapped key for the browser to unwrap"
  end

  test "blank password is rejected and leaves the password unchanged" do
    digest_before = @user.password_digest

    patch password_path(@token), params: @keys.merge(password: ""), as: :json

    assert_response :unprocessable_entity
    assert_equal digest_before, @user.reload.password_digest
    assert User.authenticate_by(email_address: @user.email_address, password: AUTH_HASH),
      "original password must still work since the reset did not happen"
  end

  test "missing password param is rejected rather than reported as success" do
    digest_before = @user.password_digest

    patch password_path(@token), params: @keys.except(:password), as: :json

    assert_response :unprocessable_entity
    assert_equal digest_before, @user.reload.password_digest
  end

  test "blank password does not destroy existing sessions" do
    @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

    patch password_path(@token), params: @keys.merge(password: ""), as: :json

    assert_equal 1, @user.sessions.count,
      "sessions must survive a reset that did not actually change the password"
  end

  test "recovery-code path swaps the password material, keeps the blob, revokes sessions, and signs in" do
    @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    @user.create_encrypted_blob!(ciphertext: "keep", nonce: "n")

    patch password_path(@token), params: @keys, as: :json

    assert_response :success
    assert_equal @user.id, response.parsed_body["account"]
    @user.reload
    assert User.authenticate_by(email_address: @user.email_address, password: NEW_AUTH_HASH)
    assert_equal '{"nonce":"p","ciphertext":"q"}', @user.password_wrapped_key
    assert_equal '{"nonce":"r","ciphertext":"s"}', @user.recovery_wrapped_key
    assert_equal "keep", @user.encrypted_blob.ciphertext
    assert_equal 1, @user.sessions.count, "old sessions revoked, the reset's own session started"

    get screen_path("journal")
    assert_response :success
  end

  test "device path replaces the blob" do
    @user.create_encrypted_blob!(ciphertext: "old", nonce: "n")

    patch password_path(@token), params: @keys.merge(blob: { ciphertext: "rekeyed", nonce: "n2" }), as: :json

    assert_response :success
    assert_equal "rekeyed", @user.reload.encrypted_blob.ciphertext
  end

  test "device path creates the blob when none exists" do
    patch password_path(@token), params: @keys.merge(blob: { ciphertext: "first", nonce: "n1" }), as: :json

    assert_response :success
    assert_equal "first", @user.reload.encrypted_blob.ciphertext
  end

  test "wipe path destroys the blob" do
    @user.create_encrypted_blob!(ciphertext: "old", nonce: "n")

    patch password_path(@token), params: @keys.merge(wipe: true), as: :json

    assert_response :success
    assert_nil @user.reload.encrypted_blob
  end

  test "an invalid blob rejects the whole reset" do
    @user.create_encrypted_blob!(ciphertext: "old", nonce: "n")
    digest_before = @user.password_digest

    patch password_path(@token), params: @keys.merge(blob: { ciphertext: "", nonce: "n2" }), as: :json

    assert_response :unprocessable_entity
    @user.reload
    assert_equal digest_before, @user.password_digest
    assert_equal "old", @user.encrypted_blob.ciphertext
  end

  test "blob and wipe together are rejected" do
    patch password_path(@token), params: @keys.merge(blob: { ciphertext: "x", nonce: "n" }, wipe: true), as: :json
    assert_response :unprocessable_entity
  end

  test "missing wrapped keys are rejected" do
    patch password_path(@token), params: { password: NEW_AUTH_HASH }, as: :json
    assert_response :unprocessable_entity
  end

  test "a raw password is rejected" do
    patch password_path(@token), params: @keys.merge(password: "correct horse battery"), as: :json
    assert_response :unprocessable_entity
    assert_match(/JavaScript/, response.parsed_body["errors"].join)
  end

  test "an expired or bogus token is rejected" do
    patch password_path("bogus"), params: @keys, as: :json
    assert_response :redirect
    assert_redirected_to new_password_path
  end
end
