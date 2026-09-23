require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid with well-formed reminder_time and time_zone" do
    user = users(:danny)
    user.reminder_time = "09:30"
    user.time_zone = "America/Chicago"
    assert user.valid?

    [ "00:00", "23:59" ].each do |boundary|
      user.reminder_time = boundary
      assert user.valid?, "expected boundary #{boundary.inspect} to be valid"
    end
  end

  test "valid with nil reminder_time and time_zone" do
    user = users(:danny)
    user.reminder_time = nil
    user.time_zone = nil
    assert user.valid?
  end

  test "normalizes blank reminder_time and time_zone to nil" do
    user = users(:danny)
    user.reminder_time = ""
    user.time_zone = ""
    assert_nil user.reminder_time
    assert_nil user.time_zone
  end

  test "rejects malformed reminder_time" do
    user = users(:danny)
    [ "9:30", "24:00", "09:60", "morning" ].each do |bad|
      user.reminder_time = bad
      assert_not user.valid?, "expected #{bad.inspect} to be invalid"
      assert_includes user.errors[:reminder_time], "is invalid"
    end
  end

  test "rejects unknown time_zone" do
    user = users(:danny)
    user.time_zone = "Mars/Olympus_Mons"
    assert_not user.valid?
    assert_includes user.errors[:time_zone], "is not a valid time zone"
  end

  test "password must be an auth hash, never a raw password" do
    user = User.new(email_address: "k@example.com", invite_code: invite_codes(:danny_invite), counselor: counselors(:logan),
      password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY)

    user.password = "correct horse battery staple"
    assert_not user.valid?
    assert_includes user.errors[:password], "requires JavaScript to be enabled"

    user.password = AUTH_HASH
    assert user.valid?, user.errors.full_messages.to_sentence
  end

  test "wrapped keys are required and bounded" do
    user = User.new(email_address: "k@example.com", invite_code: invite_codes(:danny_invite), counselor: counselors(:logan), password: AUTH_HASH)
    assert_not user.valid?
    assert_includes user.errors[:password_wrapped_key], "can't be blank"
    assert_includes user.errors[:recovery_wrapped_key], "can't be blank"

    user.password_wrapped_key = "x" * (User::WRAPPED_KEY_MAX_BYTES + 1)
    user.recovery_wrapped_key = WRAPPED_KEY
    assert_not user.valid?
    assert_includes user.errors[:password_wrapped_key], "is too long (maximum is #{User::WRAPPED_KEY_MAX_BYTES} characters)"
  end

  test "password format does not apply to updates that leave the password alone" do
    user = users(:danny)
    user.last_reminded_on = Date.current
    assert user.valid?, "updating unrelated attributes must not trigger password validation"
  end

  test "invalid with an email address that already has an account" do
    user = User.new(email_address: "danny@example.com",
      password: AUTH_HASH, password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY,
      invite_code: invite_codes(:danny_invite), counselor: counselors(:logan))
    assert_not user.valid?
    assert user.errors[:email_address].any?,
      "a duplicate email must fail validation instead of raising at the database"
  end

  test "duplicate email detection survives normalization differences" do
    user = User.new(email_address: "  DANNY@example.com ",
      password: AUTH_HASH, password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY,
      invite_code: invite_codes(:danny_invite), counselor: counselors(:logan))
    assert_not user.valid?
  end

  test "invalid without an email address" do
    user = User.new(password: AUTH_HASH, password_wrapped_key: WRAPPED_KEY, recovery_wrapped_key: WRAPPED_KEY,
      invite_code: invite_codes(:danny_invite), counselor: counselors(:logan))
    assert_not user.valid?
    assert user.errors[:email_address].any?
  end

  test "touch_last_synced! writes at most every ten minutes" do
    user = users(:danny)
    user.touch_last_synced!
    first = user.reload.last_synced_at
    assert first
    user.touch_last_synced!
    assert_equal first, user.reload.last_synced_at
    user.update_column(:last_synced_at, 11.minutes.ago)
    user.touch_last_synced!
    assert_operator user.reload.last_synced_at, :>, first
  end
end
