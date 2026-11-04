# Mirrors locke's User (app/models/user.rb) in the parts BusBar touches:
# has_secure_password with a 12-character minimum, deterministic encryption
# on email (so it can still be looked up), non-deterministic encryption on
# name and otp_secret, email normalized and unique per tenant, create
# callbacks that fill otp_secret, webauthn_id and public_id, and a time zone
# validated against ActiveSupport::TimeZone. Locke's not_pwned check is left
# out because it calls a web service.
class User < ApplicationRecord
  acts_as_tenant :tenant

  has_secure_password

  encrypts :email, deterministic: true
  encrypts :otp_secret, :name

  enum :theme, %w[system light dark].index_by(&:itself), prefix: true, validate: true

  has_many :identities, dependent: :destroy

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates_uniqueness_to_tenant :email
  validates :password, allow_nil: true, length: { minimum: 12 }
  validates :name, length: { maximum: 100 }
  validate :time_zone_exists

  normalizes :email, with: -> { _1.strip.downcase }
  normalizes :name, with: -> { _1.squish.presence }

  before_validation on: :create do
    self.otp_secret = SecureRandom.alphanumeric(32).upcase
  end

  before_validation on: :create do
    self.webauthn_id = SecureRandom.urlsafe_base64(48)
  end

  # The OIDC sub claim: random and permanent, unlike the email
  before_validation on: :create do
    self.public_id ||= "usr_#{SecureRandom.base58(24)}"
  end

  private

  def time_zone_exists
    errors.add(:time_zone, "isn't a time zone we know") unless ActiveSupport::TimeZone[time_zone.to_s]
  end
end
