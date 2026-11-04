module Busbar
  class ReviewsController < ApplicationController
    PAGE_SIZE = 100

    before_action :set_run

    def show
      authorize_busbar!(:review, @run)
      @totals = @run.staged_rows.group(:status, :action).count
      @filter = params[:filter].presence_in(%w[errors create update unchanged all]) || "errors"
      rows = @run.staged_rows.order(:row_number)
      rows = case @filter
      when "errors" then rows.with_errors
      when "all" then rows
      else rows.where(action: @filter)
      end
      @page = [ params[:page].to_i, 1 ].max
      @rows = rows.offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
    end

    # Approving the review starts the load.
    def update
      authorize_busbar!(:approve, @run)
      Runs.approve(@run, user: busbar_user) if @run.in_state?(:ready)
      redirect_to run_path(@run)
    end
  end
end
