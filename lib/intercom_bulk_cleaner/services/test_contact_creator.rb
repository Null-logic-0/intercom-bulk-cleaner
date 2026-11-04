module IntercomBulkCleaner
	module Services
		# Use this only to test bulk deletion with mock users.
		# Do not use it in a real application, as it will add fake users to your Intercom list.
		class TestContactCreator
			def initialize(contacts_api, job_waiter, run_repository, count:)
				@contacts_api = contacts_api
				@job_waiter = job_waiter
				@run_repository = run_repository
				@count = count
			end

			def call
				run_id = "#{Time.now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"
				prefix = "#{Repositories::RunRepository::PREFIX}#{run_id}"

				contacts = @count.times.map do |index|
					external_id = "#{prefix}-#{index + 1}"
					{
						external_id: external_id,
						email: "#{external_id}@example.com",
						name: "Bulk Cleaner Test User #{index + 1}",
						role: "user"
					}
				end

				puts "Creating #{@count} test contacts..."
				response = @contacts_api.create_bulk(contacts)
				job_id = response.fetch("id")
				puts "Creation job ID: #{job_id}"

				@job_waiter.call(job_id)
				@run_repository.save(prefix)

				puts "Created #{@count} test contacts."
				puts "Run prefix: #{prefix}"
			end
		end
	end
end
