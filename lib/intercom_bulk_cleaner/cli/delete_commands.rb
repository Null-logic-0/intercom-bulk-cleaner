module IntercomBulkCleaner
	class CLI
		# delete and verify.
		module DeleteCommands
			private

			# delete FILE: preview, confirm, delete.
			def delete(args)
				options = parse_delete_options(args)
				return unless options

				raise ValidationError, "Pass one file to delete (got #{args.size})." if args.size > 1

				@deps.deleter.call(
					path: args.first,
					test_run: options[:test_run],
					dry_run: options[:dry_run],
					verify: options[:verify]
				)
			end

			# verify FILE: deleted contacts must return 404.
			def verify(args)
				if args.size != 1 || %w[-h --help].include?(args.first)
					puts "Usage: bin/intercom-cleaner verify FILE   (e.g. logs/deleted_<timestamp>.csv)"
					return
				end

				records = Repositories::DeletionFile.new(args.first).load
				@deps.verifier.call(Validators::DeletionValidator.new.validate!(records))
			end

			# Options hash, or nil after printing --help.
			def parse_delete_options(args)
				options = { verify: true }

				OptionParser.new do |opts|
					opts.banner = "Usage: bin/intercom-cleaner delete FILE [options]"
					opts.separator ""
					opts.separator "Permanently deletes the contacts listed in FILE: any CSV (with an \"id\" column),"
					opts.separator "JSON or JSONL export, e.g. one made by search-export or export-all."
					opts.separator ""
					opts.on("--dry-run", "Check the file and show what would be deleted, without deleting.") { options[:dry_run] = true }
					opts.on("--test-run", "Only allow contacts from the last create-test run (FILE defaults to EXPORT_FILE).") { options[:test_run] = true }
					opts.on("--no-verify", "Skip checking each contact afterwards (one request per contact).") { options[:verify] = false }
					opts.on("-h", "--help", "Show this help.") do
						puts opts
						options[:help] = true
					end
				end.parse!(args)

				options[:help] ? nil : options
			end
		end
	end
end
