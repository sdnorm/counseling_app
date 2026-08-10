# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create a default invite code for local development
invite = InviteCode.find_or_create_by!(code: "DEVCODE1") do |code|
  code.email_address = "dev@example.com"
  code.used = false
end
puts "Dev invite code: DEVCODE1"

# Create a seed dev user for local testing (already consumes the invite code)
user = User.find_or_initialize_by(email_address: "dev@example.com")
if user.new_record?
  user.password = "password123"
  user.password_confirmation = "password123"
  user.invite_code = invite
  user.save!
  invite.update!(used: true)
  puts "Dev user: dev@example.com / password123"
else
  puts "Dev user already exists: dev@example.com"
end
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
