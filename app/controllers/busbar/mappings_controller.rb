module Busbar
  class MappingsController < ApplicationController
    before_action :set_run

    def show
      authorize_busbar!(:map, @run)
      @template = @run.template || Template.new(schema_key: @run.schema_key, column_map: @run.suggestions)
    end

    def update
      authorize_busbar!(:map, @run)
      return redirect_to(run_path(@run)) unless @run.in_state?(:awaiting_mapping)

      @template = Runs.confirm_mapping(
        @run, column_map: params.fetch(:column_map, {}).permit!.to_h, user: busbar_user,
        natural_key: params[:natural_key].presence && params[:natural_key].split("+"),
        template_name: params[:template_name], load_mode: params[:load_mode]
      )
      if @template.persisted? && @template.errors.empty?
        redirect_to run_path(@run)
      else
        render :show, status: :unprocessable_entity
      end
    end
  end
end
