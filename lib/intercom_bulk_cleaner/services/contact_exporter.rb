module IntercomBulkCleaner
	module Services
		class ContactExporter
			def initialize(contacts_api, run_repository, export_repository,
			               expected_count:)
				@contacts_api = contacts_api
				@run_repository = run_repository
				@export_repository = export_repository
				@expected_count = expected_count
			end

			def call
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

						users << {
							id: contact.fetch("id"),
							external_id: external_id,
							role: contact["role"],
							email: contact["email"]
						}
					end

					next_cursor = response.dig("pages", "next", "starting_after")
					puts "Page #{page_number}: #{contacts.size} contacts; #{users.size} matches"

					break unless next_cursor
					raise Error, "Pagination cursor did not advance." if next_cursor == cursor

					cursor = next_cursor
				end

				users.uniq! { |user| user[:external_id] }

				unless users.size == @expected_count
					raise ValidationError,
					      "Expected #{@expected_count} unique test contacts, found #{users.size}. Export aborted."
				end

				@export_repository.save(users)
				puts "Exported #{users.size} contacts to #{@export_repository.path}."
				puts "No contacts have been deleted."
			end
		end
	end
end
