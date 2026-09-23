# app/controllers/dashboard/accounts_controller.rb
class Dashboard::AccountsController < Dashboard::BaseController
  def edit
  end

  def update
    attrs = params.require(:account).permit(:name, :password, :password_confirmation)
    if attrs[:password].present? && !current_counselor.authenticate(params.dig(:account, :current_password).to_s)
      flash.now[:alert] = "Current password is incorrect."
      return render :edit, status: :unprocessable_entity
    end
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?

    if current_counselor.update(attrs)
      redirect_to edit_counselor_account_path, notice: "Account updated."
    else
      flash.now[:alert] = current_counselor.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end
end
