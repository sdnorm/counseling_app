# test/mailers/counselor_invites_mailer_test.rb
require "test_helper"

class CounselorInvitesMailerTest < ActionMailer::TestCase
  test "member invite links to the practice host" do
    invite = CounselorInvite.create!(email_address: "kim@example.com", role: "member", practice: practices(:crossroads), invited_by: counselors(:logan))
    mail = CounselorInvitesMailer.invite(invite)
    assert_equal [ "kim@example.com" ], mail.to
    assert_match %r{https://app\.crossroadcounselor\.com/counselor/setup/#{invite.token}}, mail.text_part.body.to_s
    assert_match(/Crossroads Professional Counseling/, mail.subject)
  end

  test "owner invite for a new practice links to the product host" do
    invite = CounselorInvite.create!(email_address: "pat@example.com", role: "owner", practice_name: "Calm Waters")
    mail = CounselorInvitesMailer.invite(invite)
    assert_match %r{https://example\.com/counselor/setup/#{invite.token}}, mail.text_part.body.to_s
  end
end
