module Busbar
  class RunsController < ApplicationController
    before_action :set_run, only: %i[show cancel rerun_after_ingestion]

    def index
      authorize_busbar!(:index, Run)
      @runs = Run.order(created_at: :desc).limit(100)
    end

    def show
      authorize_busbar!(:show, @run)
    end

    def new
      authorize_busbar!(:create, Run)
      @templates = Template.order(:name)
    end

    def create
      authorize_busbar!(:create, Run)
      file = params.require(:file)
      return head(:content_too_large) if file.size > Busbar.config.max_upload_size

      template = Template.find(params[:template_id]) if params[:template_id].present?
      schema = template&.schema_key || params.require(:schema)
      @run = Runs.create_from(file, tenant: current_busbar_tenant, schema: schema, template: template, user: busbar_user)
      redirect_to run_path(@run)
    end

    def cancel
      authorize_busbar!(:cancel, @run)
      Runs.cancel(@run, user: busbar_user) if @run.can_transition_to?(:cancelled)
      redirect_to run_path(@run)
    end

    def rerun_after_ingestion
      authorize_busbar!(:approve, @run)
      Runs.rerun_after_ingestion(@run) if @run.finished?
      redirect_to run_path(@run)
    end
  end
end
