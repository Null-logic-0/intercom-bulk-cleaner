module IntercomBulkCleaner
	module Services
		class DeletionVerifier
			def initialize(contacts_api)
				@contacts_api = contacts_api
			end

			def call(ids)
				remaining = []
				deleted = 0

				puts "Verifying deletion of #{ids.size} contacts..."

				ids.each_with_index do |id, index|
					begin
						@contacts_api.find(id)
						remaining << id
					rescue APIError => error
						if error.status == 404
							deleted += 1
						else
							raise
						end
					end

					puts "Verified #{index + 1}/#{ids.size}" if (index + 1) % 10 == 0
				end

				puts "Deleted: #{deleted}; still existing: #{remaining.size}"

				unless remaining.empty?
					warn "Contacts still present: #{remaining.join(', ')}"
					raise JobError, "Deletion verification failed."
				end

				puts "SUCCESS: all exported contacts were deleted."
			end
		end
	end
end
