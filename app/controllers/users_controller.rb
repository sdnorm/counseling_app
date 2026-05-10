class UsersController < ApplicationController
  allow_unauthenticated_access only: [:new, :create]

  def new
    @user = User.new
  end

  def create
    invite_code = InviteCode.find_by(code: user_params[:invite_code], used: false)
    if invite_code.nil?
      flash[:alert] = "Invalid or already used invite code."
      redirect_to new_user_path and return
    end

    @user = User.new(user_params.except(:invite_code))
    @user.invite_code = invite_code

    if @user.save
      invite_code.update!(used: true, user: @user)
      start_new_session_for @user
      redirect_to root_path, notice: "Account created successfully."
    else
      flash[:alert] = @user.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email_address, :password, :password_confirmation, :invite_code)
  end
end
