class SendGratitudeRemindersJob < ApplicationJob
  queue_as :default

  def perform
    User.where.not(reminder_time: nil)
        .where.not(time_zone: nil)
        .where(id: PushSubscription.select(:user_id))
        .find_each do |user|
      now_local = Time.current.in_time_zone(user.time_zone)
      next if now_local.strftime("%H:%M") < user.reminder_time
      next if user.last_reminded_on && user.last_reminded_on >= now_local.to_date

      begin
        user.notify_via_push(
          title: "Gratitude time",
          body: "Take a moment for your gratitude practice."
        )
        user.update!(last_reminded_on: now_local.to_date)
      rescue StandardError => e
        Rails.logger.error("Gratitude reminder failed for user #{user.id}: #{e.message}")
      end
    end
  end
end
