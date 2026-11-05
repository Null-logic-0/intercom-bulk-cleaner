module IntercomBulkCleaner
	module Repositories
		# Reads contact IDs from an export file.
		# CSV (needs an id column), JSON or JSONL.
		class DeletionFile
			FIELDS = %w[id external_id role email].freeze

			attr_reader :path

			def initialize(path)
				@path = path
			end

			# Returns [{id, external_id, role, email}, ...].
			def load
				raise ValidationError, "File not found: #{@path}" unless File.file?(@path)

				records =
					case File.extname(@path).downcase
					when ".json" then from_json
					when ".jsonl" then from_jsonl
					else from_csv
					end

				raise ValidationError, "#{@path} contains no contacts." if records.empty?

				records
			end

			private

			def from_csv
				table = CSV.read(@path, headers: true, encoding: "bom|utf-8")
				headers = table.headers.compact.map { |header| header.strip.downcase }
				unless headers.include?("id")
					raise ValidationError,
					      "#{@path} needs an \"id\" column with Intercom contact IDs (found: #{headers.join(', ')})."
				end

				table.map do |row|
					normalized = row.to_h.transform_keys { |key| key.to_s.strip.downcase }
					pick(normalized)
				end
			end

			def from_json
				data = JSON.parse(File.read(@path))
				data = data["data"] if data.is_a?(Hash) && data["data"].is_a?(Array)
				raise ValidationError, "#{@path} must contain an array of contacts." unless data.is_a?(Array)

				data.map { |contact| pick(contact) }
			rescue JSON::ParserError => error
				raise ValidationError, "Invalid JSON in #{@path}: #{error.message}"
			end

			def from_jsonl
				File.foreach(@path).with_index(1).filter_map do |line, number|
					next if line.strip.empty?

					pick(JSON.parse(line))
				rescue JSON::ParserError => error
					raise ValidationError, "Invalid JSON on line #{number} of #{@path}: #{error.message}"
				end
			end

			# Keep only the fields delete needs.
			def pick(record)
				raise ValidationError, "Every entry in #{@path} must be an object." unless record.is_a?(Hash)

				FIELDS.to_h { |field| [field, record[field].nil? ? nil : record[field].to_s.strip] }
			end
		end
	end
end
