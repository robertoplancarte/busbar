class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.bigint :identity_provider_id
      t.string :uid, null: false
      t.string :email
      t.timestamps
    end
    add_index :identities, %i[tenant_id provider identity_provider_id uid], unique: true, nulls_not_distinct: true,
              name: "index_identities_on_tenant_provider_and_uid"
  end
end
