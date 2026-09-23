class CreateActivityDays < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_days do |t|
      t.references :user, null: false, foreign_key: true
      t.date :day, null: false
      t.timestamps
    end
    add_index :activity_days, [ :user_id, :day ], unique: true
  end
end
