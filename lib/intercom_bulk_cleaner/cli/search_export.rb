module IntercomBulkCleaner
	class CLI
		# search-export and export-all.
		module SearchExport
			private

			# search-export: filters and/or bulk emails -> file.
			def search_export(args)
				options = SearchOptions.parse(args)
				return unless options

				bulk = load_bulk(options)
				check_search_options!(options, bulk)

				queries = @deps.runner.queries_for(base: base_query(options), bulk: bulk, batch_size: options[:batch_size])
				sort = Services::ContactSearch.parse_sort(options[:sort])
				return print_dry_run(queries, sort) if options[:dry_run]

				# Count first. Skipped for bulk: that would cost one request per batch.
				if options[:count] || !bulk
					total = @deps.runner.count(queries)
					puts "#{total} contacts match."
					return if options[:count] || total.zero?
				end

				export_to_file(queries, sort, options, bulk)
			end

			# export-all: everyone of a role.
			def export_all(args)
				search_export(["--all"] + args)
			end

			# Exactly one way to pick contacts: --all, filters, a query file, or a bulk list.
			def check_search_options!(options, bulk)
				filters = !options[:filters].empty?
				query_file = !options[:query_file].nil?

				raise ValidationError, "Use either --filter or --query-file, not both." if filters && query_file
				if options[:all] && (filters || query_file || bulk)
					raise ValidationError, "--all exports everything, so it can't be combined with filters or a bulk list."
				end
				return if options[:all] || filters || query_file || bulk

				raise ValidationError, "Add --emails/--emails-file, a --filter or a --query-file, or pass --all (or use export-all)."
			end

			# The filter part of the query, role included.
			def base_query(options)
				builder = @deps.query_builder
				return builder.build_all(role: options[:role]) if options[:all]
				return builder.from_file(options[:query_file], role: options[:role]) if options[:query_file]

				builder.build_base(filters: options[:filters], match: options[:match], role: options[:role])
			end

			# Emails from --emails and --emails-file. nil if neither.
			def load_bulk(options)
				values = options[:bulk_values].dup
				values.concat(Search::BulkValues.from_file(options[:bulk_file], field: options[:bulk_by]).values) if options[:bulk_file]
				return nil if values.empty? && !options[:bulk_file]

				Search::BulkValues.new(options[:bulk_by], values)
			end

			# Show the request body instead of sending it.
			def print_dry_run(queries, sort)
				body = { query: queries.first, pagination: { per_page: Services::ContactSearch::MAX_PER_PAGE } }
				body[:sort] = sort if sort
				puts JSON.pretty_generate(body)
				puts "(batch 1 of #{queries.size}; the other batches use the same filters with the next values)" if queries.size > 1
			end

			def export_to_file(queries, sort, options, bulk)
				kind = options[:all] ? "all" : (bulk ? "bulk" : "search")

				@deps.runner.run(
					queries: queries,
					output: options[:output] || Services::SearchExportRunner.default_output(kind, options[:format]),
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
		end
	end
end
