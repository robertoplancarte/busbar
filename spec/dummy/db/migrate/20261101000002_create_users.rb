# Same columns and indexes as locke's users table (db/schema.rb).
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.boolean :verified, null: false, default: false
      t.boolean :otp_required_for_sign_in, null: false, default: false
      t.string :otp_secret, null: false
      t.string :webauthn_id, null: false
      t.string :name
      t.string :time_zone, null: false, default: "Etc/UTC"
      t.string :theme, null: false, default: "system"
      t.string :public_id, null: false, index: { unique: true }
      t.timestamps
    end
    add_index :users, %i[tenant_id email], unique: true
  end
end
