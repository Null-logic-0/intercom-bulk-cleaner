module IntercomBulkCleaner
	module API
		# Intercom contacts endpoints.
		class ContactsAPI
			def initialize(client)
				@client = client
			end

			# Bulk create. Returns a job.
			def create_bulk(contacts)
				@client.post(
					"/contacts/bulk",
					{
						contacts: contacts
					}
				)
			end

			# List all contacts, page by page.
			def list(params = {})
				@client.get("/contacts", params)
			end

			# One contact by ID. 404 if gone.
			def find(id)
				escaped_id = URI::DEFAULT_PARSER.escape(id.to_s)
				@client.get("/contacts/#{escaped_id}")
			end

			# Search with filters. One page per call.
			def search(query:, per_page: 150, starting_after: nil, sort: nil)
				pagination = { per_page: per_page }
				pagination[:starting_after] = starting_after if starting_after

				body = { query: query, pagination: pagination }
				body[:sort] = sort if sort

				# Read-only, so safe to retry.
				@client.post("/contacts/search", body, idempotent: true)
			end

			# Bulk delete by ID. Returns a job.
			def delete_bulk(ids)
				@client.post(
					"/contacts/bulk/delete",
					{
						contacts: ids.map { |id| { id: id } }
					}
				)
			end
		end
	end
end
