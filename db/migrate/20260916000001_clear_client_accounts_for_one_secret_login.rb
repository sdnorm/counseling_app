class ClearClientAccountsForOneSecretLogin < ActiveRecord::Migration[8.1]
  # One-secret login has no migration path from password + passphrase
  # accounts. Launch starts fresh: the counselor re-invites every client.
  def up
    execute "DELETE FROM sessions"
    execute "DELETE FROM push_subscriptions"
    execute "DELETE FROM encrypted_blobs"
    execute "DELETE FROM users"
    execute "DELETE FROM invite_codes"
  end

  def down
    # Deleted rows are gone; nothing to restore.
  end
end
