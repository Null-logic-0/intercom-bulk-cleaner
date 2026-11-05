module IntercomBulkCleaner
	class App
		# Delete, verify and test tools.
		module DeleteFlows
			# Pick a file -> preview -> type to confirm -> delete.
			def delete_flow(path: nil, test_run: false)
				# Test runs use their own export file.
				path ||= choose_file("Which file should be deleted?", export_files, kind: "export") unless test_run
				return if path.nil? && !test_run

				plan = @deleter.plan(path: path, test_run: test_run)
				show_plan(plan)

				@ui.warning("This permanently deletes #{@ui.paint(@ui.number(plan.ids.size), :bold)} contacts" \
				            "#{workspace_name ? " from #{@ui.paint(workspace_name, :bold)}" : ''}.")
				answer = @ui.ask("Type #{@ui.paint(plan.phrase, :red, :bold)} to confirm, or press enter to cancel:", required: false)
				unless answer == plan.phrase
					@ui.warning("Cancelled. Nothing was deleted.")
					return
				end

				log_path = run_deletion(plan)
				@ui.success("Deleted #{@ui.number(plan.ids.size)} contacts in #{plan.batches.size} " \
				            "batch#{'es' unless plan.batches.size == 1}.")
				@ui.info("IDs saved to #{log_path}")

				verify_ids(plan.ids) if @ui.yes?("Verify now? (one request per contact)", default: true)
			end

			# Pick a deletion log -> check each contact is gone.
			def verify_flow
				path = choose_file("Which deletion log?", files_in(@logs_dir, "deleted_*.csv"), kind: "log")
				return if path.nil?

				records = Repositories::DeletionFile.new(path).load
				verify_ids(Validators::DeletionValidator.new.validate!(records))
			end

			# Create, export or delete fake contacts.
			def test_tools_flow
				@ui.muted("Fake contacts let you try bulk deletion without touching real data.")
				choice = @ui.select("Test tools", [
					["Create fake test contacts", :create],
					["Export the last test run", :export],
					["Delete the last test run", :delete],
					["Back", :back]
				])

				case choice
				when :create
					@creator.call if @ui.yes?("Create test contacts in Intercom now?")
				when :export
					@test_exporter.call
				when :delete
					delete_flow(test_run: true)
				end
			end

			private

			# Red summary box + preview table.
			def show_plan(plan)
				lines = [
					"File      #{plan.path}",
					"Contacts  #{@ui.paint(@ui.number(plan.ids.size), :bold)}",
					"Batches   #{plan.batches.size}"
				]
				roles = plan.roles
				lines << "Roles     #{roles.map { |role, count| "#{role} #{@ui.number(count)}" }.join(', ')}" unless roles.empty?
				lines << "Test run  #{plan.prefix}" if plan.prefix
				lines << @ui.paint("#{plan.duplicates} duplicate IDs ignored", :yellow) if plan.duplicates.positive?

				@ui.say
				@ui.box("Permanent deletion", lines, color: :red)
				@ui.table(%w[Email Role ID], plan.records.first(PREVIEW_ROWS).map { |r| [r["email"] || "-", r["role"] || "-", r["id"]] })
				@ui.muted("  ... and #{@ui.number(plan.records.size - PREVIEW_ROWS)} more") if plan.records.size > PREVIEW_ROWS
				@ui.say
			end

			# Delete with a progress bar.
			def run_deletion(plan)
				bar = @ui.progress("Deleting", total: plan.batches.size)
				done = 0

				@deleter.execute(
					plan,
					on_batch_start: ->(index, total, size) { bar.update(done, detail: "batch #{index}/#{total}: submitting #{size}") },
					on_job_state: ->(_job, state) { bar.update(done, detail: "job #{state}") },
					on_batch_done: ->(index, _total) { bar.update(done = index, detail: nil) },
					on_failure: lambda { |index, total|
						bar.finish
						finished = index == 1 ? "No batches had finished." : "Batches 1-#{index - 1} finished."
						@ui.error("Deletion stopped on batch #{index}/#{total}. #{finished}")
					}
				).tap { bar.finish }
			end

			# Check IDs with a progress bar.
			def verify_ids(ids)
				bar = @ui.progress("Verifying", total: ids.size)
				remaining = @verifier.check(ids) { |done, _total| bar.update(done) }
				bar.finish

				if remaining.empty?
					@ui.success("All #{@ui.number(ids.size)} contacts are gone. Intercom answers 404 for each.")
					@ui.muted("  Intercom keeps deleted data for a 7-day grace period before destroying it.")
				else
					@ui.error("#{@ui.number(remaining.size)} of #{@ui.number(ids.size)} contacts still exist:")
					remaining.first(10).each { |id| @ui.say "    #{id}" }
					@ui.muted("    ...") if remaining.size > 10
				end
			end
		end
	end
end
