module IntercomBulkCleaner
	module Search
		# A list of values (usually emails) to look up in bulk.
		# A list of emails (or IDs) to look up at once.
		class BulkValues
			FIELDS = %w[email id external_id phone name email_domain].freeze
			DEFAULT_BATCH_SIZE = 50
			EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/.freeze
			CASE_INSENSITIVE_FIELDS = %w[email email_domain].freeze

			attr_reader :field, :values, :skipped

			# .txt: one per line. .csv: the email column.
			def self.from_file(path, field: "email")
				raise ValidationError, "File not found: #{path}" unless File.file?(path)

				content = File.read(path, encoding: "bom|utf-8")
				first_line = content.lines.first.to_s

				raw =
					if path.downcase.end_with?(".csv") || first_line.include?(",")
						read_csv(content, field)
					else
						lines = content.lines.map(&:strip)
						lines.shift if lines.first&.casecmp?(field)
						lines
					end

				new(field, raw)
			end

			# Split pasted text on commas, spaces, new lines.
			def self.from_text(text, field: "email")
				new(field, text.to_s.split(/[\s,;]+/))
			end

			# Use the column named like the field, else the first.
			def self.read_csv(content, field)
				rows = CSV.parse(content)
				return [] if rows.empty?

				header = rows.first.map { |cell| cell.to_s.strip.downcase }
				index = header.index(field.downcase) || header.index("email")

				if index
					rows.drop(1).map { |row| row[index] }
				else
					rows.map(&:first)
				end
			end
			private_class_method :read_csv

			# Clean, de-duplicate and check the values.
			def initialize(field, raw_values)
				unless FIELDS.include?(field)
					raise ValidationError, "Bulk search works on: #{FIELDS.join(', ')} (got #{field.inspect})."
				end

				@field = field
				@values = []
				@skipped = []
				seen = Set.new

				Array(raw_values).each do |raw|
					value = clean(raw)
					next if value.empty?

					if field == "email" && !value.match?(EMAIL_PATTERN)
						@skipped << value
						next
					end

					@values << value if seen.add?(key(value))
				end

				raise ValidationError, "No valid #{field} values to search for." if @values.empty?
			end

			def size
				@values.size
			end

			# Groups for "FIELD IN [...]" requests.
			# Emails also sent lowercase: Intercom matching is case sensitive.
			def batches(batch_size = DEFAULT_BATCH_SIZE)
				raise ValidationError, "Batch size must be at least 1." unless batch_size.to_i >= 1

				@values.each_slice(batch_size.to_i).map do |slice|
					if CASE_INSENSITIVE_FIELDS.include?(@field)
						slice.flat_map { |value| [value, value.downcase] }.uniq
					else
						slice
					end
				end
			end

			# Compare key. Emails ignore case.
			def key(value)
				CASE_INSENSITIVE_FIELDS.include?(@field) ? value.to_s.downcase : value.to_s
			end

			# Values that matched no contact.
			def missing(found_keys)
				@values.reject { |value| found_keys.include?(key(value)) }
			end

			private

			# Trim spaces, quotes and mailto:.
			def clean(raw)
				value = raw.to_s.strip
				value = value[1..-2].strip if value.length >= 2 && value.start_with?('"', "'") && value.end_with?('"', "'")
				value = value.sub(/\Amailto:/i, "") if @field == "email"
				value
			end
		end
	end
end
