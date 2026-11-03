# As in locke: querying a tenant-scoped model with no tenant raises.
ActsAsTenant.configure do |config|
  config.require_tenant = true
end
