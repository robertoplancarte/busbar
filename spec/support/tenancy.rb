# Every example starts with no current tenant, so a test that forgets to set
# one fails the same way a tenant-less job would (the dummy app sets
# require_tenant, as locke does).
RSpec.configure do |config|
  config.before { ActsAsTenant.current_tenant = nil }
  config.after { ActsAsTenant.current_tenant = nil }
end

module TenancyHelpers
  def create_tenant(name)
    Tenant.create!(name: name, subdomain: name.parameterize)
  end

  def create_user(tenant, email:, name: nil, **attrs)
    ActsAsTenant.with_tenant(tenant) { User.create!(email: email, name: name, password: "correct horse battery", **attrs) }
  end
end

RSpec.configure { |c| c.include TenancyHelpers }
