# app/mailers/counselor_invites_mailer.rb
class CounselorInvitesMailer < ApplicationMailer
  def invite(invite)
    @invite = invite
    @brand = Brand.new(invite.practice)
    @setup_url = counselor_setup_url(invite.token, host: @brand.host, protocol: "https")
    subject = invite.practice ? "You're invited to join #{@brand.name}" : "Set up #{invite.practice_name} on #{@brand.product_name}"
    mail to: invite.email_address, from: from_for(@brand), subject: subject
  end
end
