module IntercomBulkCleaner
	module Services
		# Search + export. Used by the CLI and the app.
		# Handles bulk batches and the not-found list.
		class SearchExportRunner
			# What an export produced.
			Result = Struct.new(:exported, :output, :bulk_total, :missing, :missing_path, :skipped, keyword_init: true) do
				def matched
					bulk_total && bulk_total - missing.size
				end
			end

			def initialize(query_builder, searcher, exporter, out: $stdout)
				@query_builder = query_builder
				@searcher = searcher
				@exporter = exporter
				@out = out
			end

			# One query per bulk batch: (FIELD IN batch) AND filters.
			def queries_for(base:, bulk: nil, batch_size: Search::BulkValues::DEFAULT_BATCH_SIZE)
				return [base] unless bulk

				bulk.batches(batch_size).map do |batch|
					@query_builder.combine(base, { "field" => bulk.field, "operator" => "IN", "value" => batch })
				end
			end

			# Total matches across all queries.
			def count(queries)
				queries.sum { |query| @searcher.count(query) }
			end

			# Export everything. Returns a Result.
			def run(queries:, output:, bulk: nil, role: "user", **export_options)
				found_keys = Set.new
				on_contact =
					if bulk
						->(contact) { found_keys << bulk.key(contact[bulk.field]) unless contact[bulk.field].nil? }
					end

				if bulk
					@out.puts "Searching #{bulk.size} #{bulk.field} values in #{queries.size} " \
					          "batch#{'es' unless queries.size == 1}..."
				end

				exported = @exporter.call(queries: queries, output: output, on_contact: on_contact, **export_options)
				result = Result.new(exported: exported, output: exported.positive? ? output : nil, missing: [], skipped: [])
				return result unless bulk

				result.missing, result.missing_path = report_bulk(bulk, found_keys, output, role)
				result.bulk_total = bulk.size
				result.skipped = bulk.skipped
				result
			end

			# exports/contacts_<kind>_<time>.<format>
			def self.default_output(kind, format)
				"exports/contacts_#{kind}_#{Time.now.strftime('%Y%m%d-%H%M%S')}.#{format}"
			end

			private

			# Print and save the values that matched nothing.
			def report_bulk(bulk, found_keys, output, role)
				missing = bulk.missing(found_keys)
				@out.puts "Matched #{bulk.size - missing.size} of #{bulk.size} #{bulk.field} values."

				unless bulk.skipped.empty?
					@out.puts "Skipped #{bulk.skipped.size} invalid values: #{preview(bulk.skipped)}"
				end
				return [missing, nil] if missing.empty?

				path = output.sub(/\.[^.\/]+\z/, "") + "_not_found.txt"
				FileUtils.mkdir_p(File.dirname(path))
				File.write(path, missing.join("\n") + "\n")

				@out.puts "Not found: #{missing.size} (#{preview(missing)}). Full list: #{path}"
				unless role == "all"
					@out.puts "Only role=#{role} was searched. Use --role all to include #{role == 'user' ? 'leads' : 'users'}."
				end
				[missing, path]
			end

			# First 5 items, for messages.
			def preview(list)
				shown = list.first(5).join(", ")
				list.size > 5 ? "#{shown}, ..." : shown
			end
		end
	end
end
