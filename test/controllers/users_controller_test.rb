require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "signup form prefills the invite code from a shared link" do
    get new_user_path(code: "ABCD1234")

    assert_response :success
    assert_select "input[name='user[invite_code]'][value='ABCD1234']"
  end

  test "signup form leaves the invite code blank without a shared link" do
    get new_user_path

    assert_response :success
    assert_select "input[name='user[invite_code]']:not([value])"
  end

  test "signup with a valid invite code creates the account and consumes the code" do
    code = InviteCode.generate("newclient@example.com", counselor: counselors(:logan))

    assert_difference -> { User.count }, 1 do
      post users_path, params: { user: {
        email_address: "newclient@example.com",
        password: NEW_AUTH_HASH,
        password_wrapped_key: WRAPPED_KEY,
        recovery_wrapped_key: WRAPPED_KEY,
        invite_code: code.code
      } }
    end

    assert_redirected_to root_path
    code.reload
    assert code.used?
    assert_equal User.find_by(email_address: "newclient@example.com"), code.user
  end

  test "signup with an unknown invite code is rejected" do
    assert_no_difference -> { User.count } do
      post users_path, params: { user: {
        email_address: "nobody@example.com",
        password: NEW_AUTH_HASH,
        password_wrapped_key: WRAPPED_KEY,
        recovery_wrapped_key: WRAPPED_KEY,
        invite_code: "BOGUS123"
      } }
    end
    assert_response :unprocessable_entity
  end

  test "signup with an already used invite code is rejected" do
    code = InviteCode.generate("taken@example.com", counselor: counselors(:logan))
    InviteCode.claim(code.code)

    assert_no_difference -> { User.count } do
      post users_path, params: { user: {
        email_address: "second@example.com",
        password: NEW_AUTH_HASH,
        password_wrapped_key: WRAPPED_KEY,
        recovery_wrapped_key: WRAPPED_KEY,
        invite_code: code.code
      } }
    end
    assert_response :unprocessable_entity
  end

  test "a rejected signup releases the invite code instead of burning it" do
    code = InviteCode.generate("retry@example.com", counselor: counselors(:logan))

    assert_no_difference -> { User.count } do
      post users_path, params: { user: {
        email_address: "retry@example.com",
        password: "short",
        password_wrapped_key: WRAPPED_KEY,
        recovery_wrapped_key: WRAPPED_KEY,
        invite_code: code.code
      } }
    end

    assert_response :unprocessable_entity
    assert_not code.reload.used?,
      "a failed signup must leave the code usable for a second attempt"
  end

  test "a rejected signup tells the user why" do
    code = InviteCode.generate("why@example.com", counselor: counselors(:logan))

    post users_path, params: { user: {
      email_address: "why@example.com",
      password: "short",
      password_wrapped_key: WRAPPED_KEY,
      recovery_wrapped_key: WRAPPED_KEY,
      invite_code: code.code
    } }

    assert_response :unprocessable_entity
    assert_match(/requires JavaScript/i, response.body,
      "the signup form must show why the account was rejected")
  end

  test "an invalid invite code is explained on the form" do
    post users_path, params: { user: {
      email_address: "why2@example.com",
      password: NEW_AUTH_HASH,
      password_wrapped_key: WRAPPED_KEY,
      recovery_wrapped_key: WRAPPED_KEY,
      invite_code: "BOGUS123"
    } }

    assert_response :unprocessable_entity
    assert_match(/invite code/i, response.body)
  end

  test "signup with an email that already has an account is rejected with sign-in guidance" do
    code = InviteCode.generate("danny@example.com", counselor: counselors(:logan))

    assert_no_difference -> { User.count } do
      post users_path, params: { user: {
        email_address: "DANNY@example.com",
        password: NEW_AUTH_HASH,
        password_wrapped_key: WRAPPED_KEY,
        recovery_wrapped_key: WRAPPED_KEY,
        invite_code: code.code
      } }
    end

    assert_response :unprocessable_entity
    assert_match(/sign in/i, response.body,
      "the form must point an existing account holder at sign-in")
    assert_select "a[href=?]", new_session_path, { minimum: 1 },
      "the form must link to sign-in"
    assert_select "a[href=?]", new_password_path, { minimum: 1 },
      "the form must link to password reset"
    assert_not code.reload.used?,
      "a rejected duplicate signup must leave the code usable"
  end

  test "a duplicate email that slips past validation is still rejected cleanly" do
    code = InviteCode.generate("race@example.com", counselor: counselors(:logan))
    user = User.new(email_address: "race@example.com",
      password: NEW_AUTH_HASH,
      password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY)
    user.define_singleton_method(:save) do |**|
      raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed: users.email_address"
    end

    User.stub :new, user do
      assert_no_difference -> { User.count } do
        post users_path, params: { user: {
          email_address: "race@example.com",
          password: NEW_AUTH_HASH,
          password_wrapped_key: WRAPPED_KEY,
          recovery_wrapped_key: WRAPPED_KEY,
          invite_code: code.code
        } }
      end
    end

    assert_response :unprocessable_entity
    assert_not code.reload.used?,
      "a signup lost to the unique-index race must release the code"
  end

  test "the invite code is still usable after a failed attempt" do
    code = InviteCode.generate("retry2@example.com", counselor: counselors(:logan))

    post users_path, params: { user: {
      email_address: "retry2@example.com",
      password: "short",
      password_wrapped_key: WRAPPED_KEY,
      recovery_wrapped_key: WRAPPED_KEY,
      invite_code: code.code
    } }

    assert_difference -> { User.count }, 1 do
      post users_path, params: { user: {
        email_address: "retry2@example.com",
        password: NEW_AUTH_HASH,
        password_wrapped_key: WRAPPED_KEY,
        recovery_wrapped_key: WRAPPED_KEY,
        invite_code: code.code
      } }
    end
    assert_redirected_to root_path
  end

  test "JSON signup creates the account with both wrapped keys and returns the account id" do
    code = InviteCode.generate("json@example.com", counselor: counselors(:logan))

    assert_difference -> { User.count }, 1 do
      post users_path, params: { user: {
        email_address: "json@example.com",
        password: NEW_AUTH_HASH,
        invite_code: code.code,
        password_wrapped_key: WRAPPED_KEY,
        recovery_wrapped_key: WRAPPED_KEY
      } }, as: :json
    end

    assert_response :created
    user = User.find_by(email_address: "json@example.com")
    assert_equal user.id, response.parsed_body["account"]
    assert_equal WRAPPED_KEY, user.password_wrapped_key
    assert_equal WRAPPED_KEY, user.recovery_wrapped_key
    assert User.authenticate_by(email_address: "json@example.com", password: NEW_AUTH_HASH)
  end

  test "JSON signup starts a session" do
    code = InviteCode.generate("session@example.com", counselor: counselors(:logan))
    post users_path, params: { user: {
      email_address: "session@example.com", password: NEW_AUTH_HASH, invite_code: code.code,
      password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY
    } }, as: :json

    get screen_path("journal")
    assert_response :success
  end

  test "JSON signup without wrapped keys is rejected and explains why" do
    code = InviteCode.generate("nokeys@example.com", counselor: counselors(:logan))

    assert_no_difference -> { User.count } do
      post users_path, params: { user: {
        email_address: "nokeys@example.com", password: NEW_AUTH_HASH, invite_code: code.code
      } }, as: :json
    end

    assert_response :unprocessable_entity
    assert_match(/wrapped key/i, response.parsed_body["errors"].join)
    assert_not code.reload.used?
  end

  test "JSON signup with a bad invite code is rejected with an error list" do
    post users_path, params: { user: {
      email_address: "bad@example.com", password: NEW_AUTH_HASH, invite_code: "NOPE0000",
      password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY
    } }, as: :json

    assert_response :unprocessable_entity
    assert_equal [ "Invalid or already used invite code." ], response.parsed_body["errors"]
  end

  test "signup attaches the client to the inviting counselor" do
    code = InviteCode.generate("attach@example.com", counselor: counselors(:jo))
    post users_path, params: { user: {
      email_address: "attach@example.com", password: NEW_AUTH_HASH, invite_code: code.code,
      password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY
    } }, as: :json
    assert_response :created
    assert_equal counselors(:jo), User.find_by(email_address: "attach@example.com").counselor
  end
end
