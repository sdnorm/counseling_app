# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Web Push subscription key material — enough to send notifications to a
  # client's device, so it must never reach the logs.
  :p256dh, :auth,
  # Client-side encrypted payloads.
  :ciphertext, :nonce
]
