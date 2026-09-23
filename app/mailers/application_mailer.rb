class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  private

  # Mail is sent from the product domain (one Mailgun domain for everyone);
  # the practice shows up as the display name and in links.
  def from_for(brand)
    email_address_with_name("no-reply@#{Rails.application.config.x.product_host}", brand.name)
  end
end
