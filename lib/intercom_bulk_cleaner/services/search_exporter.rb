module IntercomBulkCleaner
	module Services
		# Saves search results as CSV, JSON or JSONL.
		# Writes page by page, so big exports use little memory.
		class SearchExporter
			FORMATS = %w[csv json jsonl].freeze

			def initialize(searcher, out: $stdout)
				@searcher = searcher
				@out = out
			end

			# Run the queries, write one file. Returns the count.
			def call(output:, query: nil, queries: nil, format: "csv", sort: nil, columns: nil,
			         all_columns: false, limit: nil, iso_dates: true, on_contact: nil, on_progress: nil)
				queries ||= [query]
				raise ValidationError, "Nothing to search for." if queries.empty? || queries.any?(&:nil?)
				raise ValidationError, "Format must be one of: #{FORMATS.join(', ')}" unless FORMATS.include?(format)

				FileUtils.mkdir_p(File.dirname(output))
				partial_path = "#{output}.partial.jsonl"

				exported = fetch_to(partial_path, queries: queries, sort: sort, limit: limit, on_contact: on_contact,
				                               on_progress: on_progress)

				if exported.zero?
					File.delete(partial_path) if File.exist?(partial_path)
					@out.puts "No contacts matched. Nothing was written."
					return 0
				end

				case format
				when "jsonl" then File.rename(partial_path, output)
				when "json" then write_json(partial_path, output)
				when "csv"
					write_csv(partial_path, output, columns: columns, all_columns: all_columns, iso_dates: iso_dates)
				end
				File.delete(partial_path) if File.exist?(partial_path)

				@out.puts "Exported #{exported} contacts to #{output}."
				exported
			end

			private

			# Download every page into a temp file, skipping duplicates.
			def fetch_to(path, queries:, sort:, limit:, on_contact:, on_progress: nil)
				seen = Set.new
				exported = 0
				batched = queries.size > 1

				File.open(path, "w") do |file|
					catch(:done) do
						queries.each_with_index do |query, index|
							@searcher.each_page(query: query, sort: sort) do |contacts, total, page_number|
								contacts.each do |contact|
									throw :done if limit && exported >= limit
									next unless seen.add?(contact["id"])

									file.puts(JSON.generate(contact))
									exported += 1
									on_contact&.call(contact)
								end

								if on_progress
									target = batched ? nil : (limit ? [limit, total].min : total)
									on_progress.call(exported, target, index + 1, queries.size)
								elsif batched
									@out.puts "Batch #{index + 1}/#{queries.size}, page #{page_number}: #{exported} contacts so far"
								else
									target = limit ? [limit, total].min : total
									@out.puts "Page #{page_number}: #{exported}/#{target} contacts"
								end
								throw :done if limit && exported >= limit
							end
						end
					end
				end

				exported
			end

			# Read contacts back from the temp file.
			def each_contact(path)
				File.foreach(path) { |line| yield JSON.parse(line) }
			end

			# Temp file to JSON array.
			def write_json(partial_path, output)
				File.open(output, "w") do |file|
					file.write("[\n")
					first = true
					File.foreach(partial_path) do |line|
						file.write(",\n") unless first
						file.write(line.chomp)
						first = false
					end
					file.write("\n]\n")
				end
			end

			# Temp file to CSV. First pass finds all columns.
			def write_csv(partial_path, output, columns:, all_columns:, iso_dates:)
				flattener = ContactFlattener.new(iso_dates: iso_dates)

				seen_keys = []
				seen_lookup = Set.new
				each_contact(partial_path) do |contact|
					flattener.flatten(contact).each_key { |key| seen_keys << key if seen_lookup.add?(key) }
				end

				headers =
					if columns && !columns.empty?
						unknown = columns - seen_keys
						@out.puts "Warning: no exported contact has #{unknown.join(', ')}; those columns will be empty." unless unknown.empty?
						columns
					elsif all_columns
						seen_keys
					else
						flattener.default_columns(seen_keys)
					end

				CSV.open(output, "w") do |csv|
					csv << headers
					each_contact(partial_path) do |contact|
						row = flattener.flatten(contact)
						csv << headers.map { |header| row[header] }
					end
				end
			end
		end
	end
end
