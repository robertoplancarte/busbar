# Mirrors locke's Identity: a provider account (OIDC, SAML, ...) linked to a user.
class Identity < ApplicationRecord
  acts_as_tenant :tenant

  belongs_to :user

  encrypts :email
  normalizes :email, with: -> { _1.strip.downcase.presence }
end
