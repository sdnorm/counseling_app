class ManifestsController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection

  # "Add to Home Screen" reads this once per install, so it must describe the
  # host's practice: its name and icon end up on the client's phone.
  def show
    expires_in 5.minutes, public: true
    render formats: :json, content_type: "application/manifest+json"
  end
end
