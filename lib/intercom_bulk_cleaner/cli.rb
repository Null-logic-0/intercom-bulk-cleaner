module IntercomBulkCleaner
	# Command line entry: picks a command and runs it.
	class CLI
		def initialize(configuration = Configuration.new)
			client = Client.new(configuration)
			@client = client
			contacts_api = API::ContactsAPI.new(client)
			jobs_api = API::BulkJobsAPI.new(client)

			job_waiter = Services::JobWaiter.new(
				jobs_api,
				timeout: configuration.job_timeout,
				poll_interval: configuration.job_poll_interval
			)

			run_repository = Repositories::RunRepository.new(configuration.run_id_path)
			export_repository = Repositories::ExportRepository.new(configuration.export_path)

			@creator = Services::TestContactCreator.new(
				contacts_api,
				job_waiter,
				run_repository,
				count: configuration.test_count
			)

			@query_builder = Search::QueryBuilder.new
			@searcher = Services::ContactSearch.new(contacts_api)
			@runner = Services::SearchExportRunner.new(
				@query_builder,
				@searcher,
				Services::SearchExporter.new(@searcher)
			)

			@exporter = Services::ContactExporter.new(
				contacts_api,
				run_repository,
				export_repository,
			)

			@deleter = Services::ContactDeleter.new(
				contacts_api,
				job_waiter,
				run_repository,
				Validators::DeletionValidator.new,
				@verifier = Services::DeletionVerifier.new(contacts_api),
				batch_size: configuration.batch_size,
				default_test_file: configuration.export_path
			)
		end

		# Command name -> handler.
		def run(args)
			case args[0]
			when nil, "menu"
				app.run
			when "help", "-h", "--help"
				print_usage
			when "create-test"
				@creator.call
			when "search"
				app.run_flow(:search_flow)
			when "search-export"
				run_search_export(args.drop(1))
			when "export-all"
				run_search_export(["--all"] + args.drop(1))
			when "export"
				@exporter.call
			when "delete"
				run_delete(args.drop(1))
			when "verify"
				run_verify(args.drop(1))
			else
				warn "Unknown command: #{args[0]}"
				print_usage
				exit 1
			end
		rescue Error, KeyError, ArgumentError, OptionParser::ParseError => error
			warn "#{UI::Terminal.new(output: $stderr).paint('ERROR:', :red, :bold)} #{error.message}"
			exit 1
		rescue Interrupt
			warn "\nCancelled."
			exit 130
		end

		private

		# The interactive app, built on first use.
		def app
			@app ||= App.new(
				ui: UI::Terminal.new,
				query_builder: @query_builder,
				searcher: @searcher,
				deleter: @deleter,
				verifier: @verifier,
				creator: @creator,
				test_exporter: @exporter,
				whoami: lambda {
					me = @client.get("/me")
					{ name: me.dig("app", "name"), email: me["email"] }
				}
			)
		end

		# search-export / export-all: read options, search, export.
		def run_search_export(args)
			options = {
				filters: [],
				match: "all",
				role: "user",
				format: "csv",
				iso_dates: true,
				bulk_by: "email",
				bulk_values: [],
				batch_size: Search::BulkValues::DEFAULT_BATCH_SIZE
			}

			parser = OptionParser.new do |opts|
				opts.banner = "Usage: bin/intercom-cleaner search-export [options]"
				opts.separator ""
				opts.separator "Bulk search (look up many contacts at once):"
				opts.on("-e", "--emails LIST", Array, "Comma-separated emails.") do |value|
					options[:bulk_values].concat(value)
				end
				opts.on("-E", "--emails-file PATH", "File of emails: .txt (one per line) or .csv (email column).") do |value|
					options[:bulk_file] = value
				end
				opts.on("--bulk-by FIELD", Search::BulkValues::FIELDS,
				        "Field the bulk list holds: #{Search::BulkValues::FIELDS.join(', ')} (default email).") do |value|
					options[:bulk_by] = value
				end
				opts.on("--batch-size N", Integer, "Values per request (default #{Search::BulkValues::DEFAULT_BATCH_SIZE}).") do |value|
					options[:batch_size] = value
				end
				opts.separator ""
				opts.separator "Filters (combine freely with bulk search):"
				opts.on("-f", "--filter EXPR", 'One filter, "FIELD OPERATOR VALUE". Repeat for more.') do |value|
					options[:filters] << value
				end
				opts.on("--match MODE", %w[all any], "Combine --filter values with AND (all, default) or OR (any).") do |value|
					options[:match] = value
				end
				opts.on("-q", "--query-file PATH", "Raw Intercom query JSON, for nested AND/OR groups.") do |value|
					options[:query_file] = value
				end
				opts.on("--role ROLE", %w[user lead all], "Contact role: user (default), lead or all.") do |value|
					options[:role] = value
				end
				opts.on("-a", "--all", "Export every contact of --role, no filters (same as export-all).") do
					options[:all] = true
				end
				opts.separator ""
				opts.separator "Output:"
				opts.on("--format FORMAT", Services::SearchExporter::FORMATS, "csv (default), json or jsonl.") do |value|
					options[:format] = value
				end
				opts.on("-o", "--output PATH", "Output file (default: exports/contacts_<kind>_<timestamp>.<format>).") do |value|
					options[:output] = value
				end
				opts.on("--columns LIST", Array, "CSV columns to include, comma-separated.") do |value|
					options[:columns] = value
				end
				opts.on("--all-columns", "CSV: include every field found on the contacts.") do
					options[:all_columns] = true
				end
				opts.on("--unix-timestamps", "CSV: keep *_at fields as Unix seconds instead of ISO 8601.") do
					options[:iso_dates] = false
				end
				opts.on("--sort FIELD[:asc|desc]", "Sort results, e.g. created_at:asc.") do |value|
					options[:sort] = value
				end
				opts.on("--limit N", Integer, "Stop after N contacts.") do |value|
					options[:limit] = value
				end
				opts.separator ""
				opts.separator "Inspect:"
				opts.on("--count", "Only print how many contacts match.") do
					options[:count] = true
				end
				opts.on("--dry-run", "Print the query that would be sent and exit.") do
					options[:dry_run] = true
				end
				opts.on("-h", "--help", "Show this help.") do
					puts opts
					puts search_help
					return
				end
			end

			parser.parse!(args)
			raise ValidationError, "Unexpected arguments: #{args.join(' ')}" unless args.empty?

			bulk = load_bulk(options)
			has_filters = !options[:filters].empty? || options[:query_file]

			if options[:query_file] && !options[:filters].empty?
				raise ValidationError, "Use either --filter or --query-file, not both."
			end
			if options[:all] && (has_filters || bulk)
				raise ValidationError, "--all exports everything, so it can't be combined with filters or a bulk list."
			end
			if !options[:all] && !has_filters && !bulk
				raise ValidationError,
				      "Add --emails/--emails-file, a --filter or a --query-file, or pass --all (or use export-all)."
			end

			base =
				if options[:all]
					@query_builder.build_all(role: options[:role])
				elsif options[:query_file]
					@query_builder.from_file(options[:query_file], role: options[:role])
				else
					@query_builder.build_base(filters: options[:filters], match: options[:match], role: options[:role])
				end
			queries = @runner.queries_for(base: base, bulk: bulk, batch_size: options[:batch_size])
			sort = Services::ContactSearch.parse_sort(options[:sort])

			if options[:dry_run]
				body = { query: queries.first, pagination: { per_page: Services::ContactSearch::MAX_PER_PAGE } }
				body[:sort] = sort if sort
				puts JSON.pretty_generate(body)
				puts "(batch 1 of #{queries.size}; the other batches use the same filters with the next values)" if queries.size > 1
				return
			end

			if options[:count] || !bulk
				total = @runner.count(queries)
				puts "#{total} contacts match."
				return if options[:count] || total.zero?
			end

			kind = options[:all] ? "all" : (bulk ? "bulk" : "search")
			output = options[:output] || Services::SearchExportRunner.default_output(kind, options[:format])

			@runner.run(
				queries: queries,
				output: output,
				bulk: bulk,
				role: options[:role],
				format: options[:format],
				sort: sort,
				columns: options[:columns],
				all_columns: options[:all_columns],
				limit: options[:limit],
				iso_dates: options[:iso_dates]
			)
		end

		# delete FILE: preview, confirm, delete.
		def run_delete(args)
			options = { verify: true }

			parser = OptionParser.new do |opts|
				opts.banner = "Usage: bin/intercom-cleaner delete FILE [options]"
				opts.separator ""
				opts.separator "Permanently deletes the contacts listed in FILE: any CSV (with an \"id\" column),"
				opts.separator "JSON or JSONL export, e.g. one made by search-export or export-all."
				opts.separator ""
				opts.on("--dry-run", "Check the file and show what would be deleted, without deleting.") do
					options[:dry_run] = true
				end
				opts.on("--test-run", "Only allow contacts from the last create-test run (FILE defaults to EXPORT_FILE).") do
					options[:test_run] = true
				end
				opts.on("--no-verify", "Skip checking each contact afterwards (one request per contact).") do
					options[:verify] = false
				end
				opts.on("-h", "--help", "Show this help.") do
					puts opts
					return
				end
			end

			parser.parse!(args)
			raise ValidationError, "Pass one file to delete (got #{args.size})." if args.size > 1

			@deleter.call(
				path: args.first,
				test_run: options[:test_run],
				dry_run: options[:dry_run],
				verify: options[:verify]
			)
		end

		# verify FILE: deleted contacts must return 404.
		def run_verify(args)
			if args.size != 1 || %w[-h --help].include?(args.first)
				puts "Usage: bin/intercom-cleaner verify FILE   (e.g. logs/deleted_<timestamp>.csv)"
				return
			end

			records = Repositories::DeletionFile.new(args.first).load
			ids = Validators::DeletionValidator.new.validate!(records)
			@verifier.call(ids)
		end

		# Emails from --emails and --emails-file.
		def load_bulk(options)
			from_list = options[:bulk_values].empty? ? nil : options[:bulk_values]
			from_file = options[:bulk_file]
			return nil unless from_list || from_file

			values = []
			values.concat(from_list) if from_list
			values.concat(Search::BulkValues.from_file(from_file, field: options[:bulk_by]).values) if from_file

			Search::BulkValues.new(options[:bulk_by], values)
		end

		# Extra help: operators, fields, examples.
		def search_help
			builder = Search::QueryBuilder
			<<~HELP

			  Operators (put spaces around them):
			    =  !=  IN  NIN  <  >  <=  >=  ~ (contains)  !~ (doesn't contain)  ^ (starts with)  $ (ends with)
			    IN / NIN take a comma-separated list: "email_domain IN gmail.com,yahoo.com"

			  Fields:
			    String:  #{builder::STRING_FIELDS.join(', ')}
			    Integer: #{builder::INTEGER_FIELDS.join(', ')}
			    Boolean: #{builder::BOOLEAN_FIELDS.join(', ')}
			    Date:    #{builder::DATE_FIELDS.join(', ')}
			    Custom:  custom_attributes.<name>

			  Date fields only take =, < and >, and Intercom matches them by calendar day
			  in your workspace's timezone:
			    created_at = 2026-01-15   created on that day
			    created_at < 2026-01-15   created before that day
			    created_at > 2026-01-15   created from 2026-01-16 onwards
			  Values can be YYYY-MM-DD, a Unix timestamp, or Nd for "N days ago".
			  tag_id only takes = and !=. Max #{builder::MAX_FILTERS_PER_GROUP} filters per group, #{builder::MAX_NESTING} levels of nesting.

			  Bulk search sends the list in batches of "email IN [...]" and writes the
			  values nothing matched to <output>_not_found.txt.

			  Examples:
			    bin/intercom-cleaner search                                    guided menu
			    bin/intercom-cleaner search-export -E emails.csv --role all     bulk lookup from a file
			    bin/intercom-cleaner search-export -e a@x.com,b@y.com -f "last_seen_at < 90d"
			    bin/intercom-cleaner export-all                                every user to CSV
			    bin/intercom-cleaner search-export -f "email_domain = gmail.com" -f "last_seen_at < 90d"
			    bin/intercom-cleaner search-export -f "created_at > 2026-01-01" -f "custom_attributes.plan = pro" --format json
			    bin/intercom-cleaner search-export -f "email ~ test" -f "email ~ example" --match any --count
			    bin/intercom-cleaner search-export -q examples/search_query.json --columns id,email,name,created_at
			HELP
		end

		# Command overview.
		def print_usage
			puts <<~USAGE
			  INTERCOM BULK CLEANER

			    Usage:
			  	  bin/intercom-cleaner                           (interactive app: menus, previews, progress)
			  	  bin/intercom-cleaner search                    (jump straight to the guided search)
			  	  bin/intercom-cleaner search-export [options]   (see --help)
			  	  bin/intercom-cleaner export-all [options]      (all contacts; same output options)
			  	  bin/intercom-cleaner delete FILE [--dry-run]   (any export with contact IDs; see --help)
			  	  bin/intercom-cleaner verify FILE               (check the contacts in FILE are gone)

			    Test helpers (only for trying out bulk delete with fake contacts):
			  	  bin/intercom-cleaner create-test
			  	  bin/intercom-cleaner export
			  	  bin/intercom-cleaner delete --test-run
			USAGE
		end
	end
end
