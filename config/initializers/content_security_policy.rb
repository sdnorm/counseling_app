# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    policy.form_action :self
    policy.frame_ancestors :none
    policy.object_src  :none

    # Nonce-based, see nonce_directives below. There are no hand-written inline
    # scripts, so importmap's generated tags are the only ones needing a nonce.
    policy.script_src  :self

    # The screens use inline style attributes throughout. A nonce in style-src
    # makes browsers ignore 'unsafe-inline' and would blank the UI, so style-src
    # is deliberately kept out of nonce_directives.
    policy.style_src   :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.font_src    :self, :data, "https://fonts.gstatic.com"
    policy.img_src     :self, :data
    policy.manifest_src :self
    policy.worker_src  :self

    # The resources screen fetches the counseling practice's public feed.
    policy.connect_src :self, "https://crossroadcounselor.com"
  end

  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
