class AddReminderFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :reminder_time, :string
    add_column :users, :time_zone, :string
    add_column :users, :last_reminded_on, :date
  end
end
