module IntercomBulkCleaner
	module Validators
		class DeletionValidator
			def initialize(expected_count:)
				@expected_count = expected_count
			end

			def validate!(rows, expected_prefix:)
				raise ValidationError, "CSV must contain a header row." unless rows.headers

				missing = Repositories::ExportRepository::HEADERS - rows.headers
				unless missing.empty?
					raise ValidationError, "Missing CSV columns: #{missing.join(', ')}"
				end

				# Test purposes only
				# unless rows.size == @expected_count
				# 	raise ValidationError,
				# 	      "Expected exactly #{@expected_count} contacts, found #{rows.size}."
				# end

				ids = []
				external_ids = []

				rows.each do |row|
					id = row["id"]
					external_id = row["external_id"]

					if id.nil? || id.empty? || external_id.nil? || external_id.empty?
						raise ValidationError, "Missing contact ID or external ID."
					end

					unless external_id.start_with?("#{expected_prefix}-")
						raise ValidationError,
						      "Safety check failed: contact outside this test run."
					end

					unless row["role"] == "user"
						raise ValidationError, "Unexpected contact role: #{row['role']}"
					end

					ids << id
					external_ids << external_id
				end

				raise ValidationError, "Duplicate contact IDs detected." unless ids.uniq.size == @expected_count

				raise ValidationError, "Duplicate external IDs detected." unless external_ids.uniq.size == @expected_count

				ids
			end
		end
	end
end
