class UsersController < ApplicationController
  allow_unauthenticated_access only: [ :new, :create ]
  layout "session"
  rate_limit to: 10, within: 10.minutes, only: :create,
    with: -> { redirect_to new_user_path, alert: "Too many sign-up attempts. Try again later." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params.except(:invite_code))

    if claim_code_and_save
      start_new_session_for @user
      redirect_to root_path, notice: "Account created successfully."
    else
      flash.now[:alert] = @error
      render :new, status: :unprocessable_entity
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
    @error = "That email address already has an account — please sign in instead."
    false
  end

  def user_params
    params.require(:user).permit(:email_address, :password, :password_confirmation, :invite_code)
  end
end
