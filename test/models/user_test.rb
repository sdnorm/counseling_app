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

  test "rejects a password shorter than the minimum" do
    user = users(:danny)
    user.password = "a" * (User::MINIMUM_PASSWORD_LENGTH - 1)
    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is #{User::MINIMUM_PASSWORD_LENGTH} characters)"
  end

  test "accepts a password at the minimum length" do
    user = users(:danny)
    user.password = "a" * User::MINIMUM_PASSWORD_LENGTH
    assert user.valid?
  end

  test "password length does not apply to updates that leave the password alone" do
    user = users(:danny)
    user.last_reminded_on = Date.current
    assert user.valid?, "updating unrelated attributes must not trigger password validation"
  end
end
