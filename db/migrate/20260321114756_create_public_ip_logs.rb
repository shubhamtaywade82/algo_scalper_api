class CreatePublicIpLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :public_ip_logs do |t|
      t.string :ip_address
      t.string :ip_version
      t.datetime :first_seen_at
      t.datetime :last_seen_at

      t.timestamps
    end
  end
end
