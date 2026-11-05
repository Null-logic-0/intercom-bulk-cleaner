module IntercomBulkCleaner
	module Services
		# Runs a search and walks through every result page.
		class ContactSearch
			MAX_PER_PAGE = 150
			SORT_ORDERS = {
				"asc" => "ascending",
				"ascending" => "ascending",
				"desc" => "descending",
				"descending" => "descending"
			}.freeze

			def initialize(contacts_api, per_page: MAX_PER_PAGE)
				@contacts_api = contacts_api
				@per_page = per_page.clamp(1, MAX_PER_PAGE)
			end

			# How many match, without downloading them.
			def count(query)
				response = @contacts_api.search(query: query, per_page: 1)
				response["total_count"].to_i
			end

			# Yields each page of results.
			def each_page(query:, sort: nil)
				cursor = nil
				page_number = 0

				loop do
					page_number += 1
					response = @contacts_api.search(
						query: query,
						per_page: @per_page,
						starting_after: cursor,
						sort: sort
					)

					yield response.fetch("data", []), response["total_count"].to_i, page_number

					next_cursor = response.dig("pages", "next", "starting_after")
					break if next_cursor.nil? || next_cursor.empty?
					raise Error, "Pagination cursor did not advance." if next_cursor == cursor

					cursor = next_cursor
				end
			end

			# All matches in one array. Small searches only.
			def all(query:, sort: nil, limit: nil)
				contacts = []
				each_page(query: query, sort: sort) do |page, _total, _number|
					contacts.concat(page)
					break if limit && contacts.size >= limit
				end
				limit ? contacts.first(limit) : contacts
			end

			# "created_at:asc" -> Intercom sort object.
			def self.parse_sort(value)
				return nil if value.nil? || value.empty?

				field, order = value.split(":", 2)
				order = SORT_ORDERS[(order || "desc").downcase]
				raise ValidationError, "Sort order must be asc or desc." unless order

				{ field: field, order: order }
			end
		end
	end
end
