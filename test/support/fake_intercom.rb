# Fake Intercom for bin/demo: same methods as the real API, data in memory.
module FakeIntercom
	DOMAINS = %w[gmail.com yahoo.com acme.io example.com outlook.com].freeze
	NAMES = %w[anna ben carla david elena farid gia hana ivan jana].freeze
	COUNTRIES = %w[Georgia Germany France Spain Brazil].freeze
	DAY = 86_400

	# 500 varied contacts: users and leads, plans, countries, dates.
	def self.sample_contacts(count = 500, now: Time.now.to_i)
		(1..count).map do |i|
			name = NAMES[i % NAMES.size]
			{
				"type" => "contact",
				"id" => format("%024x", 0x6a00000000000000 + i),
				"external_id" => (i % 3).zero? ? nil : "ext-#{i}",
				"role" => (i % 7).zero? ? "lead" : "user",
				"email" => "#{name}#{i}@#{DOMAINS[i % DOMAINS.size]}",
				"email_domain" => DOMAINS[i % DOMAINS.size],
				"name" => "#{name.capitalize} #{i}",
				"created_at" => now - (i * 1.5 * DAY).to_i,
				"last_seen_at" => (i % 5).zero? ? nil : now - ((i * 37) % 400) * DAY,
				"unsubscribed_from_emails" => (i % 11).zero?,
				"has_hard_bounced" => (i % 23).zero?,
				"location" => { "type" => "location", "country" => COUNTRIES[i % COUNTRIES.size], "city" => nil },
				"custom_attributes" => { "plan" => (i % 4).zero? ? "pro" : "free" },
				"tags" => { "type" => "list", "data" => [] },
				"companies" => { "type" => "list", "data" => [] }
			}
		end
	end

	# Contacts and bulk job endpoints.
	class API
		attr_reader :contacts

		def initialize(contacts, latency: 0)
			@contacts = contacts
			@latency = latency
			@next_job = 0
		end

		def search(query:, per_page: 150, starting_after: nil, sort: nil)
			pause
			query = JSON.parse(JSON.generate(query))
			hits = @contacts.select { |contact| match?(contact, query) }
			hits = sorted(hits, sort) if sort
			page(hits, per_page, starting_after)
		end

		def list(params = {})
			pause
			page(@contacts, (params[:per_page] || 50).to_i, params[:starting_after])
		end

		def find(id)
			contact = @contacts.find { |item| item["id"] == id }
			raise IntercomBulkCleaner::APIError.new(404, '{"type":"error.list","errors":[{"code":"not_found"}]}') unless contact

			contact
		end

		def create_bulk(new_contacts)
			pause
			new_contacts.each_with_index do |attributes, index|
				contact = JSON.parse(JSON.generate(attributes))
				contact["id"] = format("%024x", 0x6b00000000000000 + @contacts.size + index)
				contact["type"] = "contact"
				@contacts << contact
			end
			job
		end

		def delete_bulk(ids)
			pause
			@contacts.reject! { |contact| ids.include?(contact["id"]) }
			job
		end

		private

		def pause
			sleep @latency if @latency.positive?
		end

		def job
			@next_job += 1
			{ "id" => "job_demo_#{@next_job}", "state" => "pending" }
		end

		def page(items, per_page, cursor)
			start = cursor ? Integer(cursor) : 0
			next_cursor = start + per_page < items.size ? (start + per_page).to_s : nil
			{
				"type" => "list",
				"data" => items[start, per_page] || [],
				"total_count" => items.size,
				"pages" => { "next" => next_cursor && { "starting_after" => next_cursor } }
			}
		end

		def sorted(hits, sort)
			field = sort[:field] || sort["field"]
			list = hits.sort_by { |contact| value_of(contact, field).to_s }
			(sort[:order] || sort["order"]) == "descending" ? list.reverse : list
		end

		def value_of(contact, field)
			contact.dig(*field.split("."))
		end

		def match?(contact, node)
			return node["value"].public_send(node["operator"] == "AND" ? :all? : :any?) { |child| match?(contact, child) } unless node["field"]

			actual = value_of(contact, node["field"])
			expected = node["value"]
			case node["operator"]
			when "=" then actual == expected
			when "!=" then actual != expected
			when "IN" then expected.include?(actual)
			when "NIN" then !expected.include?(actual)
			when "~" then actual.to_s.downcase.include?(expected.to_s.downcase)
			when "!~" then !actual.to_s.downcase.include?(expected.to_s.downcase)
			when "^" then actual.to_s.downcase.start_with?(expected.to_s.downcase)
			when "$" then actual.to_s.downcase.end_with?(expected.to_s.downcase)
			when "<" then actual && actual < expected
			when ">" then actual && actual > expected
			when "<=" then actual && actual <= expected
			when ">=" then actual && actual >= expected
			else false
			end
		end
	end

	# Bulk jobs finish on the first check.
	class Jobs
		def find(job_id)
			{ "id" => job_id, "state" => "completed" }
		end
	end
end
