class PushNotifier
  VAPID_SUBJECT = "mailto:spencernorman@hey.com"

  def self.notify(user, title:, body:)
    message = { title: title, body: body }.to_json

    user.push_subscriptions.find_each do |subscription|
      WebPush.payload_send(
        message: message,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        vapid: {
          subject: VAPID_SUBJECT,
          public_key: Rails.application.credentials.dig(:web_push, :public_key),
          private_key: Rails.application.credentials.dig(:web_push, :private_key)
        }
      )
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      subscription.destroy
    rescue WebPush::ResponseError => e
      Rails.logger.warn("Push delivery failed for subscription #{subscription.id}: #{e.message}")
    end
  end
end
