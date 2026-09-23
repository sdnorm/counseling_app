class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    @brand = Brand.new(user.counselor.practice)
    @reset_url = edit_password_url(user.password_reset_token, host: @brand.host, protocol: "https")
    mail to: user.email_address, from: from_for(@brand), subject: "Reset your #{@brand.name} password"
  end
end
