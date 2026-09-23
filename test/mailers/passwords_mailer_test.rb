require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "reset link uses the client's practice host" do
    mail = PasswordsMailer.reset(users(:danny))
    assert_match %r{https://app\.crossroadcounselor\.com/passwords/}, mail.text_part.body.to_s
    assert_equal [ "no-reply@example.com" ], mail.from
  end
end
