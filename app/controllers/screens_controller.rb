class ScreensController < ApplicationController
  def show
    valid_screens = %w[journal gratitude emotions coping triangle checkin takeaways agenda resources settings]
    if valid_screens.include?(params[:id])
      render params[:id], layout: false
    else
      head :not_found
    end
  end
end
