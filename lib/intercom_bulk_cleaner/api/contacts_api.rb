module IntercomBulkCleaner
	module API
		class ContactsAPI
			def initialize(client)
				@client = client
			end

			def create_bulk(contacts)
				@client.post("/contacts/bulk", contacts: contacts)
			end

			def list(params = {})
				@client.get("/contacts", params)
			end

			def find(id)
				escaped_id = URI::DEFAULT_PARSER.escape(id.to_s)
				@client.get("/contacts/#{escaped_id}")
			end

			def delete_bulk(ids)
				@client.post(
					"/contacts/bulk/delete",
					contacts: ids.map { |id| { id: id } }
				)
			end
		end
	end
end
