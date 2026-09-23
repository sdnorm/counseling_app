class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_current_practice
  helper_method :brand

  private

  # The host decides which practice a page wears before anyone is logged in.
  def set_current_practice
    Current.practice = Practice.for_host(request.host)
  end

  # After a client logs in, their own counselor's practice wins over the
  # host's: the native app only ever talks to the product host, and a
  # Crossroads client there must still see Crossroads.
  def brand
    @brand ||= Brand.new(current_user&.counselor&.practice || Current.practice)
  end
end
