# app/controllers/platform/practices_controller.rb
class Platform::PracticesController < Platform::BaseController
  before_action :set_practice, only: %i[ show update ]

  def index
    @practices = Practice.includes(:counselors).order(:name)
  end

  def show
  end

  # The only place a custom domain is set: each one needs DNS and a Hatchbox
  # domain entry, which is operator work.
  def update
    if @practice.update(params.require(:practice).permit(:custom_domain, :client_limit_per_counselor, :trial_ends_at))
      redirect_to platform_practice_path(@practice), notice: "Saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_practice
    @practice = Practice.find(params[:id])
  end
end
