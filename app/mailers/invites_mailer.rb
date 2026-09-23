class InvitesMailer < ApplicationMailer
  def invite(code)
    @code = code
    @brand = Brand.new(code.counselor.practice)
    @signup_url = new_user_url(code: code.code, host: @brand.host, protocol: "https")
    mail to: code.email_address, from: from_for(@brand), subject: "Your invite to #{@brand.name}"
  end
end
