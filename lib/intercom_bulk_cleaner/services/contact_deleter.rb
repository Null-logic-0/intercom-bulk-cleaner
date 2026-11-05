module IntercomBulkCleaner
	module Services
		# Deletes the contacts listed in a file.
		# plan = check the file, execute = delete, call = CLI flow.
		class ContactDeleter
			PREVIEW_ROWS = 5

			# What will be deleted.
			Plan = Struct.new(:path, :records, :ids, :batches, :prefix, keyword_init: true) do
				def duplicates
					records.size - ids.size
				end

				def roles
					records.map { |record| record["role"] }.compact.tally
				end

				def phrase
					"DELETE #{ids.size} CONTACTS"
				end
			end

			def initialize(contacts_api, job_waiter, run_repository, validator, verifier,
			               batch_size:, default_test_file:, log_dir: "logs", input: $stdin, out: $stdout)
				@contacts_api = contacts_api
				@job_waiter = job_waiter
				@run_repository = run_repository
				@validator = validator
				@verifier = verifier
				@batch_size = batch_size
				@default_test_file = default_test_file
				@log_dir = log_dir
				@input = input
				@out = out
			end

			# Load and check the file. No API calls.
			def plan(path: nil, test_run: false)
				path ||= @default_test_file if test_run
				if path.nil?
					raise ValidationError,
					      "Pass the file to delete, e.g. bin/intercom-cleaner delete exports/contacts_search_<timestamp>.csv"
				end

				prefix = test_run ? @run_repository.load : nil
				records = Repositories::DeletionFile.new(path).load
				ids = @validator.validate!(records, expected_prefix: prefix)

				Plan.new(path: path, records: records, ids: ids, batches: ids.each_slice(@batch_size).to_a, prefix: prefix)
			end

			# Save IDs to logs/, then delete in batches. Prints nothing.
			def execute(plan, on_log: nil, on_batch_start: nil, on_job_state: nil, on_batch_done: nil, on_failure: nil)
				log_path = write_log(plan.records, plan.ids)
				on_log&.call(log_path)

				plan.batches.each_with_index do |batch, index|
					on_batch_start&.call(index + 1, plan.batches.size, batch.size)
					job_id = @contacts_api.delete_bulk(batch).fetch("id")
					@job_waiter.call(job_id) { |state| on_job_state&.call(job_id, state) }
					on_batch_done&.call(index + 1, plan.batches.size)
				rescue Error, KeyError
					on_failure&.call(index + 1, plan.batches.size)
					raise
				end

				log_path
			end

			# CLI: summary, typed confirmation, delete, verify.
			def call(path: nil, test_run: false, dry_run: false, verify: true)
				deletion = plan(path: path, test_run: test_run)
				print_summary(deletion)

				if dry_run
					say "Dry run: nothing was deleted."
					return 0
				end

				@out.print "Type #{deletion.phrase} to continue: "
				unless @input.gets&.strip == deletion.phrase
					say "Deletion cancelled. Nothing was deleted."
					return 0
				end

				execute(
					deletion,
					on_log: ->(log_path) { say "Contact list saved to #{log_path}" },
					on_batch_start: ->(index, total, size) { say "Submitting deletion batch #{index}/#{total} (#{size} contacts)..." },
					on_job_state: ->(job_id, state) { say "Job #{job_id}: #{state}" },
					on_failure: lambda { |index, total|
						finished = index == 1 ? "No batches had finished." : "Batches 1-#{index - 1} finished."
						warn "Deletion stopped on batch #{index}/#{total}. #{finished}"
					}
				)

				@verifier.call(deletion.ids) if verify
				say "Deletion workflow completed: #{deletion.ids.size} contacts."
				deletion.ids.size
			end

			private

			# Show what will be deleted.
			def print_summary(deletion)
				say
				say "PERMANENT DELETION"
				say "File:      #{deletion.path}"
				say "Contacts:  #{deletion.ids.size}"
				say "Batches:   #{deletion.batches.size} (up to #{@batch_size} per batch)"
				say "Test run:  #{deletion.prefix}" if deletion.prefix
				say "Duplicates ignored: #{deletion.duplicates}" if deletion.duplicates.positive?

				roles = deletion.roles
				say "Roles:     #{roles.map { |role, count| "#{role} #{count}" }.join(', ')}" unless roles.empty?

				say
				deletion.records.first(PREVIEW_ROWS).each do |record|
					say "  #{record['email'] || '-'} | #{record['role'] || '-'} | #{record['id']}"
				end
				say "  ... and #{deletion.records.size - PREVIEW_ROWS} more" if deletion.records.size > PREVIEW_ROWS
				say
			end

			# Save the IDs to logs/deleted_<time>.csv.
			def write_log(records, ids)
				FileUtils.mkdir_p(@log_dir)
				path = File.join(@log_dir, "deleted_#{Time.now.strftime('%Y%m%d-%H%M%S')}.csv")
				wanted = ids.to_h { |id| [id, true] }

				CSV.open(path, "w") do |csv|
					csv << Repositories::DeletionFile::FIELDS
					records.each do |record|
						next unless wanted.delete(record["id"])

						csv << Repositories::DeletionFile::FIELDS.map { |field| record[field] }
					end
				end

				path
			end

			def say(text = "")
				@out.puts text
			end
		end
	end
end
