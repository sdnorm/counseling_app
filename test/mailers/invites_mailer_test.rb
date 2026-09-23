require "test_helper"

class InvitesMailerTest < ActionMailer::TestCase
  test "invite comes from the product domain with the practice as sender name and links to the practice host" do
    code = InviteCode.generate("client@example.com", counselor: counselors(:logan))
    mail = InvitesMailer.invite(code)

    assert_equal [ "client@example.com" ], mail.to
    assert_equal [ "no-reply@example.com" ], mail.from
    assert_match(/Crossroads Professional Counseling/, mail[:from].display_names.first)
    assert_match(/Crossroads Professional Counseling/, mail.subject)
    assert_match %r{https://app\.crossroadcounselor\.com/users/new\?code=#{code.code}}, mail.text_part.body.to_s
  end
end
