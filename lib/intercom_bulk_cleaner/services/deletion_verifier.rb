module IntercomBulkCleaner
	module Services
		# Checks deleted contacts are really gone.
		class DeletionVerifier
			def initialize(contacts_api)
				@contacts_api = contacts_api
			end

			# Returns IDs that still exist (no 404).
			def check(ids)
				remaining = []

				ids.each_with_index do |id, index|
					begin
						@contacts_api.find(id)
						remaining << id
					rescue APIError => error
						raise unless error.status == 404
					end

					yield index + 1, ids.size if block_given?
				end

				remaining
			end

			# CLI version: prints results, fails if any remain.
			def call(ids)
				puts "Verifying deletion of #{ids.size} contacts..."
				remaining = check(ids) { |done, total| puts "Verified #{done}/#{total}" if (done % 10).zero? }
				puts "Deleted: #{ids.size - remaining.size}; still existing: #{remaining.size}"

				unless remaining.empty?
					warn "Contacts still present: #{remaining.join(', ')}"
					raise JobError, "Deletion verification failed."
				end

				puts "SUCCESS: all exported contacts were deleted."
			end
		end
	end
end
