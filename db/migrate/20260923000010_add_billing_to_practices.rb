class AddBillingToPractices < ActiveRecord::Migration[8.1]
  def change
    change_table :practices do |t|
      t.string :stripe_customer_id
      t.string :stripe_subscription_id
      t.string :billing_status, null: false, default: "none"
      t.string :billing_interval
      t.datetime :current_period_end
      t.boolean :complimentary, null: false, default: false
      t.references :referred_by_practice, foreign_key: { to_table: :practices }
      t.datetime :first_paid_at
      t.integer :referral_rewards_granted, null: false, default: 0
    end
    add_index :practices, :stripe_customer_id, unique: true
    add_index :practices, :stripe_subscription_id, unique: true
  end
end
