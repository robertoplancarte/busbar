class User < ApplicationRecord
  acts_as_tenant :account

  belongs_to :manager, class_name: "User", optional: true

  ROLES = %w[admin manager member].freeze
  STATUSES = %w[active suspended].freeze

  validates :email, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates_uniqueness_to_tenant :external_id, allow_nil: true
end
