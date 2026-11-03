# Like locke's: the tenant comes from the request host's subdomain
# (acme.example.com) and the signed-in user from the session. Tests sign in
# with the X-Test-User-Id header.
class ApplicationController < ActionController::Base
  set_current_tenant_through_filter
  before_action :set_tenant_from_host
  before_action :set_current_user

  private

  def set_tenant_from_host
    set_current_tenant(Tenant.find_by(subdomain: request.subdomain))
  end

  def set_current_user
    Current.user = User.find_by(id: request.headers["X-Test-User-Id"]) if ActsAsTenant.current_tenant
  end
end
