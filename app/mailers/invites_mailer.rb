class InvitesMailer < ApplicationMailer
  def invite(code)
    @code = code
    mail to: code.email_address, subject: "Your invite code for Crossroads"
  end
end
