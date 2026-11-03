# A plain model with no callbacks or encryption, loaded by BusBar's fast
# upsert_all loader on (tenant_id, external_id).
class Employee < ApplicationRecord
  acts_as_tenant :tenant

  STATUSES = %w[active leave terminated].freeze

  validates :external_id, :email, presence: true
end
