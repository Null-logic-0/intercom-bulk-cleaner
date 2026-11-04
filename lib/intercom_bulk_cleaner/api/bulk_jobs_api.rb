module IntercomBulkCleaner
	module API
		class BulkJobsAPI
			def initialize(client)
				@client = client
			end

			def find(job_id)
				escaped_id = URI::DEFAULT_PARSER.escape(job_id.to_s)
				@client.get("/contacts/bulk/#{escaped_id}")
			end
		end
	end
end
