module Busbar
  # Inherits from the host's controller (Busbar.config.parent_controller), so
  # the host's authentication and tenant filters run first. Every action
  # needs a current tenant and passes through Busbar.config.authorize, which
  # denies unless the host configured it.
  class ApplicationController < (Busbar.config.parent_controller.presence || "ActionController::Base").constantize
    layout -> { Busbar.config.layout }

    before_action :require_busbar_tenant

    rescue_from Busbar::NotAuthorized do
      respond_to do |format|
        format.html { render plain: "You are not allowed to do that.", status: :forbidden }
        format.json { render json: { error: "forbidden" }, status: :forbidden }
      end
    end

    helper_method :busbar_user, :current_busbar_tenant

    private

    def current_busbar_tenant = ActsAsTenant.current_tenant

    def busbar_user
      return @busbar_user if defined?(@busbar_user)

      @busbar_user = Busbar.config.current_user && instance_exec(&Busbar.config.current_user)
    end

    def authorize_busbar!(action, record)
      raise Busbar::NotAuthorized unless Busbar.authorized?(busbar_user, action, record)
    end

    def require_busbar_tenant
      head :not_found unless current_busbar_tenant
    end

    def set_run
      @run = Run.find(params[:run_id] || params[:id])
    end
  end
end
