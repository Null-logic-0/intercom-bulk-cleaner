module IntercomBulkCleaner
	class CLI
		# Options for search-export and export-all.
		class SearchOptions
			DEFAULTS = {
				match: "all",
				role: "user",
				format: "csv",
				iso_dates: true,
				bulk_by: "email",
				batch_size: Search::BulkValues::DEFAULT_BATCH_SIZE
			}.freeze

			# Options hash, or nil after printing --help.
			def self.parse(args)
				options = DEFAULTS.merge(filters: [], bulk_values: [])
				parser(options).parse!(args)
				return nil if options[:help]

				raise ValidationError, "Unexpected arguments: #{args.join(' ')}" unless args.empty?

				options
			end

			class << self
				private

				def parser(options)
					OptionParser.new do |opts|
						opts.banner = "Usage: bin/intercom-cleaner search-export [options]"
						bulk_options(opts, options)
						filter_options(opts, options)
						output_options(opts, options)
						inspect_options(opts, options)
					end
				end

				def bulk_options(opts, options)
					opts.separator ""
					opts.separator "Bulk search (look up many contacts at once):"
					opts.on("-e", "--emails LIST", Array, "Comma-separated emails.") { |v| options[:bulk_values].concat(v) }
					opts.on("-E", "--emails-file PATH", "File of emails: .txt (one per line) or .csv (email column).") { |v| options[:bulk_file] = v }
					opts.on("--bulk-by FIELD", Search::BulkValues::FIELDS,
					        "Field the bulk list holds: #{Search::BulkValues::FIELDS.join(', ')} (default email).") { |v| options[:bulk_by] = v }
					opts.on("--batch-size N", Integer, "Values per request (default #{Search::BulkValues::DEFAULT_BATCH_SIZE}).") { |v| options[:batch_size] = v }
				end

				def filter_options(opts, options)
					opts.separator ""
					opts.separator "Filters (combine freely with bulk search):"
					opts.on("-f", "--filter EXPR", 'One filter, "FIELD OPERATOR VALUE". Repeat for more.') { |v| options[:filters] << v }
					opts.on("--match MODE", %w[all any], "Combine --filter values with AND (all, default) or OR (any).") { |v| options[:match] = v }
					opts.on("-q", "--query-file PATH", "Raw Intercom query JSON, for nested AND/OR groups.") { |v| options[:query_file] = v }
					opts.on("--role ROLE", %w[user lead all], "Contact role: user (default), lead or all.") { |v| options[:role] = v }
					opts.on("-a", "--all", "Export every contact of --role, no filters (same as export-all).") { options[:all] = true }
				end

				def output_options(opts, options)
					opts.separator ""
					opts.separator "Output:"
					opts.on("--format FORMAT", Services::SearchExporter::FORMATS, "csv (default), json or jsonl.") { |v| options[:format] = v }
					opts.on("-o", "--output PATH", "Output file (default: exports/contacts_<kind>_<timestamp>.<format>).") { |v| options[:output] = v }
					opts.on("--columns LIST", Array, "CSV columns to include, comma-separated.") { |v| options[:columns] = v }
					opts.on("--all-columns", "CSV: include every field found on the contacts.") { options[:all_columns] = true }
					opts.on("--unix-timestamps", "CSV: keep *_at fields as Unix seconds instead of ISO 8601.") { options[:iso_dates] = false }
					opts.on("--sort FIELD[:asc|desc]", "Sort results, e.g. created_at:asc.") { |v| options[:sort] = v }
					opts.on("--limit N", Integer, "Stop after N contacts.") { |v| options[:limit] = v }
				end

				def inspect_options(opts, options)
					opts.separator ""
					opts.separator "Inspect:"
					opts.on("--count", "Only print how many contacts match.") { options[:count] = true }
					opts.on("--dry-run", "Print the query that would be sent and exit.") { options[:dry_run] = true }
					opts.on("-h", "--help", "Show this help.") do
						puts opts, Help.search
						options[:help] = true
					end
				end
			end
		end
	end
end
