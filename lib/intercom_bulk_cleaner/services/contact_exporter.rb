module IntercomBulkCleaner
	module Services
		# Test tools: exports the contacts of the last test run.
		class ContactExporter
			def initialize(contacts_api, run_repository, export_repository)
				@contacts_api = contacts_api
				@run_repository = run_repository
				@export_repository = export_repository
			end

			# Save test-run users to the export CSV.
			def call(contacts: nil)
				users = contacts ? normalize_contacts(contacts) : fetch_contacts

				raise ValidationError, "No contacts found to export." if users.empty?

				@export_repository.save(users)

				puts "Exported #{users.size} contacts to #{@export_repository.path}."
				puts "No contacts have been deleted."

				users
			end

			private

			# Find this run's contacts by external_id prefix.
			def fetch_contacts
				prefix = @run_repository.load
				users = []
				cursor = nil
				page_number = 0

				puts "Fetching contacts for run #{prefix}..."

				loop do
					page_number += 1
					params = { per_page: 150 }
					params[:starting_after] = cursor if cursor

					response = @contacts_api.list(params)
					contacts = response.fetch("data", [])

					contacts.each do |contact|
						external_id = contact["external_id"]

						next unless external_id&.start_with?("#{prefix}-")
						next unless contact["role"] == "user"

						users << contact_attributes(contact)
					end

					next_cursor = response.dig("pages", "next", "starting_after")
					puts "Page #{page_number}: #{contacts.size} contacts; #{users.size} matches"

					break unless next_cursor

					raise Error, "Pagination cursor did not advance." if next_cursor == cursor

					cursor = next_cursor
				end

				users.uniq { |user| user[:external_id] }

			end

			def normalize_contacts(contacts)
				contacts
					.select { |contact| contact["role"] == "user" }
					.map { |contact| contact_attributes(contact) }
					.uniq { |user| user[:id] }
			end

			def contact_attributes(contact)
				{
					id: contact.fetch("id"),
					external_id: contact["external_id"],
					role: contact["role"],
					email: contact["email"]
				}
			end

		end
	end
end
