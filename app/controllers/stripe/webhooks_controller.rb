#
# Stripe tells us what happened; we mirror it onto the practice. Every event
# is recorded before it is acted on so redeliveries are no-ops, and a
# practice we can't find is fine (a customer created outside the app).
class Stripe::WebhooksController < ActionController::API
  def create
    event = ::Stripe::Webhook.construct_event(request.raw_post, request.headers["Stripe-Signature"].to_s, Rails.application.config.x.stripe.webhook_secret)
  rescue JSON::ParserError, ::Stripe::SignatureVerificationError
    head :bad_request
  else
    handle(event) if StripeEvent.record!(event.id, event.type)
    head :ok
  end

  private

  def handle(event)
    object = event.data.object
    case event.type
    when "checkout.session.completed"
      practice = Practice.find_by(id: object.client_reference_id)
      practice&.apply_subscription(::Stripe::Subscription.retrieve(object.subscription)) if object.subscription
    when "customer.subscription.updated", "customer.subscription.deleted"
      practice = Practice.find_by(id: object.metadata&.to_h&.with_indifferent_access&.[](:practice_id).presence) || Practice.find_by(stripe_subscription_id: object.id)
      practice&.apply_subscription(object)
    when "invoice.paid"
      practice = Practice.find_by(stripe_customer_id: object.customer)
      return unless practice
      practice.apply_subscription(::Stripe::Subscription.retrieve(object.subscription)) if object.respond_to?(:subscription) && object.subscription
      practice.record_paid_invoice!
    when "invoice.payment_failed"
      Practice.find_by(stripe_customer_id: object.customer)&.update!(billing_status: "past_due")
    end
  end
end
