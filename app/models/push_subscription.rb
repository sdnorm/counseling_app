class PushSubscription < ApplicationRecord
  VAPID_SUBJECT = "mailto:spencernorman@hey.com"

  belongs_to :user
  validates :endpoint, :p256dh, :auth, presence: true

  after_destroy :clear_reminder_settings, unless: :destroyed_by_association

  def deliver(title:, body:)
    WebPush.payload_send(
      message: { title: title, body: body }.to_json,
      endpoint: endpoint,
      p256dh: p256dh,
      auth: auth,
      vapid: {
        subject: VAPID_SUBJECT,
        public_key: Rails.application.credentials.dig(:web_push, :public_key),
        private_key: Rails.application.credentials.dig(:web_push, :private_key)
      }
    )
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    destroy
  rescue OpenSSL::OpenSSLError, ArgumentError => e
    # Corrupt stored key material can never succeed — treat like a dead subscription.
    Rails.logger.warn("Push subscription #{id} has invalid keys (#{e.class}); removing")
    destroy
  rescue WebPush::ResponseError => e
    Rails.logger.warn("Push delivery failed for subscription #{id}: #{e.message}")
  end

  private

  def clear_reminder_settings
    return if user.push_subscriptions.where.not(id: id).exists?

    user.update(reminder_time: nil, time_zone: nil)
  end
end
