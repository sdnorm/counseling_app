module PushNotifiable
  extend ActiveSupport::Concern

  included do
    has_many :push_subscriptions, dependent: :destroy
  end

  def notify_via_push(title:, body:)
    push_subscriptions.find_each { |subscription| subscription.deliver(title: title, body: body) }
  end
end
