class CreateInviteCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :invite_codes do |t|
      t.string :code
      t.boolean :used, default: false, null: false
      t.references :user, foreign_key: true

      t.timestamps
    end
    add_index :invite_codes, :code, unique: true
  end
end
