require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "signup with a valid invite code creates the account and consumes the code" do
    code = InviteCode.generate("newclient@example.com")

    assert_difference -> { User.count }, 1 do
      post users_path, params: { user: {
        email_address: "newclient@example.com",
        password: "supersecret1",
        password_confirmation: "supersecret1",
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
        password: "supersecret1",
        password_confirmation: "supersecret1",
        invite_code: "BOGUS123"
      } }
    end
    assert_response :unprocessable_entity
  end

  test "signup with an already used invite code is rejected" do
    code = InviteCode.generate("taken@example.com")
    InviteCode.claim(code.code)

    assert_no_difference -> { User.count } do
      post users_path, params: { user: {
        email_address: "second@example.com",
        password: "supersecret1",
        password_confirmation: "supersecret1",
        invite_code: code.code
      } }
    end
    assert_response :unprocessable_entity
  end

  test "a rejected signup releases the invite code instead of burning it" do
    code = InviteCode.generate("retry@example.com")

    assert_no_difference -> { User.count } do
      post users_path, params: { user: {
        email_address: "retry@example.com",
        password: "short",
        password_confirmation: "short",
        invite_code: code.code
      } }
    end

    assert_response :unprocessable_entity
    assert_not code.reload.used?,
      "a failed signup must leave the code usable for a second attempt"
  end

  test "a rejected signup tells the user why" do
    code = InviteCode.generate("why@example.com")

    post users_path, params: { user: {
      email_address: "why@example.com",
      password: "short",
      password_confirmation: "short",
      invite_code: code.code
    } }

    assert_response :unprocessable_entity
    assert_match(/too short/i, response.body,
      "the signup form must show why the account was rejected")
  end

  test "an invalid invite code is explained on the form" do
    post users_path, params: { user: {
      email_address: "why2@example.com",
      password: "supersecret1",
      password_confirmation: "supersecret1",
      invite_code: "BOGUS123"
    } }

    assert_response :unprocessable_entity
    assert_match(/invite code/i, response.body)
  end

  test "the invite code is still usable after a failed attempt" do
    code = InviteCode.generate("retry2@example.com")

    post users_path, params: { user: {
      email_address: "retry2@example.com",
      password: "short",
      password_confirmation: "short",
      invite_code: code.code
    } }

    assert_difference -> { User.count }, 1 do
      post users_path, params: { user: {
        email_address: "retry2@example.com",
        password: "supersecret1",
        password_confirmation: "supersecret1",
        invite_code: code.code
      } }
    end
    assert_redirected_to root_path
  end
end
