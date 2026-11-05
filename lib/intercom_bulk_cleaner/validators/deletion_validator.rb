module IntercomBulkCleaner
	module Validators
		# Checks a deletion file before anything is deleted.
		class DeletionValidator
			ID_PATTERN = /\A[A-Za-z0-9_-]+\z/.freeze

			# Returns unique IDs. Rejects missing IDs and emails.
			# Test runs: every contact must belong to that run.
			def validate!(records, expected_prefix: nil)
				ids = []

				records.each_with_index do |record, index|
					id = record["id"]
					line = "entry #{index + 1}"

					raise ValidationError, "Missing contact ID in #{line}." if id.nil? || id.empty?

					if id.include?("@")
						raise ValidationError, "#{line}: #{id.inspect} looks like an email. delete needs Intercom contact IDs."
					end
					raise ValidationError, "#{line}: invalid contact ID #{id.inspect}." unless id.match?(ID_PATTERN)

					check_test_run!(record, line, expected_prefix) if expected_prefix

					ids << id
				end

				if expected_prefix
					external_ids = records.map { |record| record["external_id"] }
					raise ValidationError, "Duplicate external IDs detected." unless external_ids.uniq.size == external_ids.size
				end

				ids.uniq
			end

			private

			# Must be a user from this test run.
			def check_test_run!(record, line, prefix)
				external_id = record["external_id"].to_s
				unless external_id.start_with?("#{prefix}-")
					raise ValidationError, "Safety check failed: #{line} is outside test run #{prefix}."
				end

				return if record["role"] == "user"

				raise ValidationError, "Safety check failed: #{line} has role #{record['role'].inspect}, expected user."
			end
		end
	end
end
