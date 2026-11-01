# Every example starts with no current tenant, so a test that forgets to set
# one fails the same way a tenant-less job would.
RSpec.configure do |config|
  config.before { ActsAsTenant.current_tenant = nil }
  config.after { ActsAsTenant.current_tenant = nil }
end
