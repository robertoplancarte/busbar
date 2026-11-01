# The phase 1 target from docs/spec.md: client users, keyed per account by
# external_id (or lowercased email when the client has no id).
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :account, null: false, foreign_key: true
      t.string :external_id
      t.string :email, null: false
      t.string :first_name
      t.string :last_name
      t.string :role, null: false, default: "member"
      t.string :status, null: false, default: "active"
      t.string :title
      t.string :department
      t.references :manager, foreign_key: { to_table: :users }
      t.string :phone
      t.timestamps
    end

    # upsert_all unique_by indexes must lead with the tenant column.
    add_index :users, %i[account_id external_id], unique: true, where: "external_id IS NOT NULL"
    add_index :users, "account_id, lower(email)", unique: true, name: "index_users_on_account_id_and_lower_email"
  end
end
