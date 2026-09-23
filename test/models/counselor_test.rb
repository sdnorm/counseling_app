require "test_helper"

class CounselorTest < ActiveSupport::TestCase
  test "requires a 12 character password" do
    counselor = Counselor.new(practice: practices(:riverbend), email_address: "new@riverbend.example", name: "New", role: "member", password: "short")
    assert_not counselor.valid?
    counselor.password = "long enough password"
    assert counselor.valid?, counselor.errors.full_messages.to_sentence
  end

  test "role is owner or member" do
    counselor = counselors(:jo)
    counselor.role = "admin"
    assert_not counselor.valid?
  end

  test "remove! ends sessions and leaves the active scope" do
    counselor = counselors(:jo)
    counselor.sessions.create!(ip_address: "127.0.0.1", user_agent: "test")
    counselor.remove!
    assert counselor.removed?
    assert_equal 0, counselor.sessions.count
    assert_not_includes Counselor.active, counselor
  end

  test "email is unique regardless of case" do
    dup = Counselor.new(practice: practices(:riverbend), email_address: "LOGAN@crossroadcounselor.com", name: "Dup", role: "member", password: "long enough password")
    assert_not dup.valid?
  end
end
