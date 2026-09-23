# app/mailers/counselor_passwords_mailer.rb
class CounselorPasswordsMailer < ApplicationMailer
  def reset(counselor)
    @counselor = counselor
    @brand = Brand.new(counselor.practice)
    @reset_url = edit_counselor_password_url(counselor.password_reset_token, host: @brand.host, protocol: "https")
    mail to: counselor.email_address, from: from_for(@brand), subject: "Reset your counselor password"
  end
end
