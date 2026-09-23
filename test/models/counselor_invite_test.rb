require "test_helper"

class CounselorInviteTest < ActiveSupport::TestCase
  test "must target exactly one practice" do
    assert_not CounselorInvite.new(email_address: "a@example.com", role: "member").valid?
    assert_not CounselorInvite.new(email_address: "a@example.com", role: "owner", practice: practices(:riverbend), practice_name: "X").valid?
    assert CounselorInvite.new(email_address: "a@example.com", role: "member", practice: practices(:riverbend)).valid?
    assert CounselorInvite.new(email_address: "a@example.com", role: "owner", practice_name: "New Practice").valid?
  end

  test "gets a token and a seven day expiry" do
    invite = CounselorInvite.create!(email_address: "a@example.com", role: "owner", practice_name: "New Practice")
    assert invite.token.present?
    assert_in_delta 7.days.from_now, invite.expires_at, 5.seconds
    assert invite.usable?
  end

  test "accepting an owner invite creates the practice and the owner" do
    invite = CounselorInvite.create!(email_address: "owner@example.com", role: "owner", practice_name: "Calm Waters")

    counselor = invite.accept!(name: "Pat", password: "long enough password")

    assert counselor.owner?
    assert_equal "Calm Waters", counselor.practice.name
    assert_equal "calm-waters", counselor.practice.slug
    assert_in_delta 30.days.from_now, counselor.practice.trial_ends_at, 5.seconds
    assert invite.reload.accepted?
  end

  test "accepting a member invite joins the practice" do
    invite = CounselorInvite.create!(email_address: "member@example.com", role: "member", practice: practices(:riverbend), invited_by: counselors(:sam))

    counselor = invite.accept!(name: "Kim", password: "long enough password")

    assert_equal practices(:riverbend), counselor.practice
    assert_not counselor.owner?
  end

  test "an expired or accepted invite cannot be accepted, and a failed acceptance creates nothing" do
    invite = CounselorInvite.create!(email_address: "x@example.com", role: "owner", practice_name: "Expired")
    invite.update_column(:expires_at, 1.hour.ago)
    assert_raises(ActiveRecord::RecordInvalid) { invite.accept!(name: "X", password: "long enough password") }

    dup = CounselorInvite.create!(email_address: counselors(:logan).email_address, role: "owner", practice_name: "Dup Practice")
    assert_no_difference -> { Practice.count } do
      assert_raises(ActiveRecord::RecordInvalid) { dup.accept!(name: "X", password: "long enough password") }
    end
  end
end
