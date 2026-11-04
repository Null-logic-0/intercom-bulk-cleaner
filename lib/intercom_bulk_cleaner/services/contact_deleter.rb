module IntercomBulkCleaner
	module Services
		class ContactDeleter
			def initialize(contacts_api, job_waiter, export_repository,
			               run_repository, validator, verifier, batch_size:)
				@contacts_api = contacts_api
				@job_waiter = job_waiter
				@export_repository = export_repository
				@run_repository = run_repository
				@validator = validator
				@verifier = verifier
				@batch_size = batch_size
			end

			def call
				prefix = @run_repository.load
				rows = @export_repository.load
				ids = @validator.validate!(rows, expected_prefix: prefix)

				puts
				puts "PERMANENT DELETION CONFIRMATION"
				puts "Contacts: #{ids.size}"
				puts "Batches: #{(ids.size.to_f / @batch_size).ceil}"
				puts "Test prefix: #{prefix}"
				print "Type DELETE USERS to continue: "

				confirmation = STDIN.gets&.strip
				unless confirmation == "DELETE USERS"
					puts "Deletion cancelled."
					return
				end

				batches = ids.each_slice(@batch_size).to_a
				batches.each_with_index do |batch, index|
					puts "Submitting deletion batch #{index + 1}/#{batches.size}..."
					response = @contacts_api.delete_bulk(batch)
					job_id = response.fetch("id")
					puts "Deletion job ID: #{job_id}"
					@job_waiter.call(job_id)
				end

				@verifier.call(ids)
				puts "Deletion workflow completed."
			end
		end
	end
end
