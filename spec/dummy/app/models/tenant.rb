# Mirrors locke's Tenant: the acts_as_tenant tenant, with users keyed on tenant_id.
class Tenant < ApplicationRecord
  has_many :users, dependent: :restrict_with_error
  has_many :employees, dependent: :destroy

  normalizes :subdomain, with: ->(value) { value.strip.downcase }

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true
end
