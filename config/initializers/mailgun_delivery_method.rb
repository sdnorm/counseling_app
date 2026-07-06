require "mailgun-ruby"

class MailgunDeliveryMethod
  attr_accessor :settings

  def initialize(settings = {})
    @settings = settings
  end

  def deliver!(mail)
    domain = settings[:domain]
    api_key = settings[:api_key]

    raise ArgumentError, "Mailgun domain is missing" if domain.blank?
    raise ArgumentError, "Mailgun API key is missing" if api_key.blank?

    client = Mailgun::Client.new(api_key)
    message = Mailgun::MessageBuilder.new

    message.from(mail.from.first)
    message.add_recipient(:to, mail.to.first)
    message.subject(mail.subject)

    if mail.html_part
      message.body_html(mail.html_part.body.to_s)
    end

    if mail.text_part
      message.body_text(mail.text_part.body.to_s)
    elsif mail.html_part.nil?
      message.body_text(mail.body.to_s)
    end

    client.send_message(domain, message)
  end
end

# Referencing ActionMailer::Base directly here would trigger its load hooks
# before this delivery method exists, so the railtie would silently drop
# config.action_mailer.mailgun_settings and leave it as {}. Registering
# inside on_load runs after those hooks, so the settings must be re-applied
# from the environment config.
ActiveSupport.on_load(:action_mailer) do
  add_delivery_method :mailgun, MailgunDeliveryMethod
  self.mailgun_settings = Rails.application.config.action_mailer.mailgun_settings || {}
end
