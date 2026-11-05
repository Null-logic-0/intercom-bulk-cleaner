module IntercomBulkCleaner
	module Services
		# Test tools: creates fake contacts to try bulk delete safely.
		class TestContactCreator
			def initialize(contacts_api, job_waiter, run_repository, count:)
				@contacts_api = contacts_api
				@job_waiter = job_waiter
				@run_repository = run_repository
				@count = count
			end

			# Create the contacts and remember the run ID.
			def call
				run_id = "#{Time.now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"
				prefix = "#{Repositories::RunRepository::PREFIX}#{run_id}"
				created_at = Time.now.utc.to_i

				contacts = @count.times.map do |index|
					external_id = "#{prefix}-#{index + 1}"
					{
						external_id: external_id,
						email: "#{external_id}@example.com",
						name: "Bulk Cleaner Test User #{index + 1}",
						role: "user",
						created_at: created_at,
					}
				end

				puts "Creating #{@count} test contacts..."
				puts "Creation date: #{Time.at(created_at).utc}"

				response = @contacts_api.create_bulk(contacts)
				job_id = response.fetch("id")
				
				puts "Creation job ID: #{job_id}"

				@job_waiter.call(job_id)
				@run_repository.save(prefix)

				puts "Created #{@count} test contacts."
				puts "Run prefix: #{prefix}"
				puts "Created at: #{created_at}"

			end
		end
	end
end
