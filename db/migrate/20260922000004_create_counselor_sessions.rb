class CreateCounselorSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :counselor_sessions do |t|
      t.references :counselor, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
  end
end
