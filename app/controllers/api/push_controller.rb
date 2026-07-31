class Api::PushController < Api::BaseController
  allow_unauthenticated_access only: %i[ vapid_public_key ]

  def vapid_public_key
    render json: { public_key: Rails.application.credentials.dig(:web_push, :public_key) }
  end

  def create
    # Endpoints are unique per browser, not per account, so look them up globally:
    # a device reused by a second account must transfer rather than collide with
    # the unique index. Whoever is signed in owns the device from here on.
    sub = PushSubscription.find_or_initialize_by(endpoint: params[:endpoint])
    sub.user = current_user
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

  def update_preferences
    if current_user.update(preferences_params)
      render json: { success: true }
    else
      render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def preferences_params
    params.permit(:reminder_time, :time_zone)
  end
end
