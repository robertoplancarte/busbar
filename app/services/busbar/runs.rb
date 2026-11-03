module Busbar
  # Entry points that move runs between stages. Every channel ends in
  # Runs.create_from; the UI and API call the rest.
  module Runs
    module_function

    # file: an uploaded file, IO, path or ActiveStorage blob.
    def create_from(file, tenant:, schema:, filename: nil, template: nil, user: nil, review_required: true, load_mode: nil)
      raise MissingTenant, "Runs.create_from needs a tenant" unless tenant

      ActsAsTenant.with_tenant(tenant) do
        run = Run.new(tenant: tenant, schema_key: Busbar.schema(schema).key, created_by_id: user&.id,
                      review_required: review_required, load_mode: load_mode || template&.load_mode || "incremental")
        attach(run, file, filename)
        run.filename = run.file.filename.to_s
        run.save!
        run.use_template!(template) if template
        run.update!(load_mode: load_mode) if load_mode
        ActiveSupport::Notifications.instrument("run.created.busbar", run: run)
        PrepareJob.perform_later(run.id)
        run
      end
    end

    # Saves the person's mapping as a template (new, or a new version of the
    # run's) and starts staging.
    def confirm_mapping(run, column_map:, user: nil, natural_key: nil, template_name: nil, load_mode: nil, transforms: nil, value_maps: nil)
      template = run.template || Template.new(tenant: run.tenant, schema_key: run.schema_key, created_by_id: user&.id)
      template.assign_attributes({
        name: template_name.presence || template.name.presence || "#{run.schema.name} from #{run.filename}",
        column_map: column_map.to_h.compact_blank, natural_key: Array(natural_key).compact_blank,
        load_mode: load_mode.presence || template.load_mode || run.load_mode,
        transforms: transforms, value_maps: value_maps
      }.compact)
      return template unless template.save

      run.use_template!(template)
      run.transition_to!(:staging, user: user)
      StageJob.perform_later(run.id)
      template
    end

    def approve(run, user: nil)
      run.update!(approved_by_id: user&.id, approved_at: Time.current)
      start_loading(run, user: user)
    end

    def cancel(run, user: nil) = run.transition_to!(:cancelled, user: user)

    def start_loading(run, user: nil)
      run.transition_to!(:loading, user: user)
      run.chunk_count.times { |chunk| LoadChunkJob.perform_later(run.id, chunk) }
      advance_after_load(run) if run.chunk_count.zero?
    end

    # The last chunk to finish loading enqueues FinalizeJob, once.
    def advance_after_load(run)
      return if run.staged_rows.where(status: "valid").exists?

      FinalizeJob.perform_later(run.id) if run.claim!(:finalize_enqueued_at)
    end

    def rerun_after_ingestion(run) = AfterIngestionJob.perform_later(run.id)

    def attach(run, file, filename)
      case file
      when ActiveStorage::Blob then run.file.attach(file)
      when String, Pathname then run.file.attach(io: File.open(file), filename: filename || File.basename(file.to_s))
      when ActionDispatch::Http::UploadedFile then run.file.attach(file)
      else run.file.attach(io: file, filename: filename || "upload")
      end
    end
  end
end
