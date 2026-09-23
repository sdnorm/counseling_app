module PushNotifiable
  extend ActiveSupport::Concern

  included do
    has_many :push_subscriptions, dependent: :destroy
  end

  def notify_via_push(title:, body:)
    icon = push_icon_path
    push_subscriptions.find_each { |subscription| subscription.deliver(title: title, body: body, icon: icon) }
  end

  private

  # The notification wears the counselor's practice icon when there is one.
  # Same-origin paths only: the service worker resolves them against the app.
  def push_icon_path
    variant = Brand.new(counselor&.practice).icon_variant(192)
    if variant
      Rails.application.routes.url_helpers.rails_storage_proxy_path(variant, only_path: true)
    else
      ActionController::Base.helpers.image_path("generic/icon-192.png")
    end
  end
end
