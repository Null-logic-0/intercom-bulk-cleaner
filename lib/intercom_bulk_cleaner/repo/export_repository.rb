module IntercomBulkCleaner
	module Repositories
		# Test tools: CSV of test-run contacts.
		class ExportRepository
			attr_reader :path

			# Same columns delete reads.
			HEADERS = DeletionFile::FIELDS

			def initialize(path)
				@path = path
			end

			def save(users)
				FileUtils.mkdir_p(File.dirname(@path))
				CSV.open(@path, "w") do |csv|
					csv << HEADERS
					users.each do |user|
						csv << HEADERS.map { |header| user[header.to_sym] }
					end
				end
			end

			def load
				raise ValidationError, "CSV file not found: #{@path}" unless File.file?(@path)
				CSV.read(@path, headers: true)
			end
		end
	end
end
