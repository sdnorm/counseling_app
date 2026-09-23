class UsersController < ApplicationController
  allow_unauthenticated_access only: [ :new, :create ]
  layout "session"
  rate_limit to: 10, within: 10.minutes, only: :create, with: -> { too_many_attempts }

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params.except(:invite_code))

    if claim_code_and_save
      start_new_session_for @user
      respond_to do |format|
        format.html { redirect_to root_path, notice: "Account created successfully." }
        format.json { render json: { account: @user.id }, status: :created }
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:alert] = @error
          render :new, status: :unprocessable_entity
        end
        format.json { render json: { errors: [ @error ] }, status: :unprocessable_entity }
      end
    end
  end

  private

  # Claiming the code and creating the user share one transaction: the claim has
  # to be atomic so concurrent signups can't reuse a code, but a signup we then
  # reject must roll the claim back rather than burn the code.
  def claim_code_and_save
    ActiveRecord::Base.transaction do
      invite_code = InviteCode.claim(user_params[:invite_code])
      if invite_code.nil?
        @error = "Invalid or already used invite code."
        raise ActiveRecord::Rollback
      end

      @user.invite_code = invite_code
      @user.counselor = invite_code.counselor
      unless @user.save
        @error = @user.errors.full_messages.join(", ")
        raise ActiveRecord::Rollback
      end

      invite_code.update!(user: @user)
      true
    end
  # Backstop for the race where a duplicate email passes validation but loses to
  # the unique index. Rescuing outside the transaction rolls the claim back too.
  rescue ActiveRecord::RecordNotUnique
    @error = "That email address already has an account — sign in or reset your password below."
    false
  end

  def user_params
    params.require(:user).permit(:email_address, :password, :invite_code,
      :password_wrapped_key, :recovery_wrapped_key)
  end

  def too_many_attempts
    respond_to do |format|
      format.html { redirect_to new_user_path, alert: "Too many sign-up attempts. Try again later." }
      format.json { render json: { errors: [ "Too many sign-up attempts. Try again later." ] }, status: :too_many_requests }
    end
  end
end
