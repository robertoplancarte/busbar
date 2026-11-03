module Busbar
  module Schemas
    # The ready-made `user` schema, shaped after locke's User: one `name`
    # field (or first_name + last_name joined into it), an IANA time zone,
    # and a natural key of external_id when the client's file has one,
    # otherwise the lowercased email. Passwords are never imported; the
    # save loader gives new users a random one (see Loaders::ActiveRecordSave).
    #
    # Hosts adopt it as is, or replace it with Busbar.define_schema(:user).
    def self.user
      Schema.build(:user) do
        name "Users"
        natural_key :external_id
        natural_key :email
        loader :active_record_save, model: "User"

        field :external_id, :string, synonyms: [ "id", "employee id", "emp id", "employee number", "user id", "sourced id" ]
        field :email, :email, required: true, synonyms: [ "email address", "e-mail", "work email", "mail" ]
        field :name, :string, length: { maximum: 100 }, synonyms: [ "full name", "display name" ]
        field :first_name, :string, virtual: true, synonyms: [ "first", "given name", "givenname" ]
        field :last_name, :string, virtual: true, synonyms: [ "last", "surname", "family name", "familyname" ]
        field :time_zone, :time_zone, synonyms: [ "timezone", "tz", "zone" ]

        transform :name, :concat, fields: %w[first_name last_name], separator: " ", only_blank: true
      end
    end
  end
end
