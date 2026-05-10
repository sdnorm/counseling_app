class Api::PushController < Api::BaseController
  skip_before_action :authenticate_user!, only: [:vapid_public_key]

  def vapid_public_key
    render json: { public_key: Rails.application.credentials.dig(:web_push, :public_key) }
  end

  def create
    sub = current_user.push_subscriptions.find_or_initialize_by(endpoint: params[:endpoint])
    sub.assign_attributes(p256dh: params[:p256dh], auth: params[:auth])

    if sub.save
      render json: { success: true }
    else
      render json: { errors: sub.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    sub = current_user.push_subscriptions.find_by(endpoint: params[:endpoint])
    if sub
      sub.destroy
      render json: { success: true }
    else
      render json: { success: false }, status: :not_found
    end
  end
end
