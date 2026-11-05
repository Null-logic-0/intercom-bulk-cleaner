module IntercomBulkCleaner
	module Repositories
		# Test tools: remembers the last create-test run.
		class RunRepository
			PREFIX = "bulk-cleaner-test-"

			def initialize(path)
				@path = path
			end

			# Store the run ID.
			def save(prefix)
				raise ValidationError, "Invalid test run prefix." unless prefix.start_with?(PREFIX)

				FileUtils.mkdir_p(File.dirname(@path))
				File.write(@path, prefix)
			end

			# Read the run ID. Fails if there is none.
			def load
				raise ValidationError, "No test run found. Run create-test first." unless File.file?(@path)

				prefix = File.read(@path).strip
				unless prefix.start_with?(PREFIX) && prefix.length > PREFIX.length
					raise ValidationError, "Invalid test run identifier in #{@path}."
				end

				prefix
			end
		end
	end
end
