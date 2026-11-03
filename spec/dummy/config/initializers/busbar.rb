Busbar.configure do |c|
  c.tenant_class  = "Tenant"
  c.tenant_column = :tenant_id
  c.user_class    = "User"
  c.current_user  = -> { Current.user if defined?(Current) }

  # BusBar denies every action until you decide who may import data.
  # (user, action, record) -> true/false. Actions: :index, :show, :create,
  # :map, :review, :approve, :cancel. For example, a per-tenant admin check:
  #
  #   c.authorize = ->(user, _action, _record) { user&.admin_of?(ActsAsTenant.current_tenant) }
  c.authorize = ->(_user, _action, _record) { false }

  # Engine controllers inherit from this, so your authentication and tenant
  # filters run first.
  c.parent_controller = "::ApplicationController"
  c.layout = "application"

  # Side effects after a run loads, per schema (or :default).
  # c.after_ingestion = { user: "UserIngestionHandler" }
end
