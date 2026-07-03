class PushSubscription < ApplicationRecord
  VAPID_SUBJECT = "mailto:spencernorman@hey.com"

  belongs_to :user
  validates :endpoint, :p256dh, :auth, presence: true

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
  rescue WebPush::ResponseError => e
    Rails.logger.warn("Push delivery failed for subscription #{id}: #{e.message}")
  end
end
