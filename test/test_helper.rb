require "minitest/autorun"
require "stringio"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "intercom_bulk_cleaner"

module TestSupport
	include IntercomBulkCleaner

	# In-memory stand-in for ContactsAPI#search. It evaluates =, IN, ~ and
	# AND/OR groups, and pages with a numeric starting_after cursor.
	class FakeContactsAPI
		attr_reader :calls

		def initialize(contacts)
			@contacts = contacts
			@calls = []
		end

		def search(query:, per_page: 150, starting_after: nil, sort: nil)
			query = JSON.parse(JSON.generate(query))
			@calls << { query: query, per_page: per_page, starting_after: starting_after, sort: sort }

			hits = @contacts.select { |contact| match?(contact, query) }
			start = starting_after ? Integer(starting_after) : 0
			next_cursor = start + per_page < hits.size ? (start + per_page).to_s : nil

			{
				"type" => "list",
				"data" => hits[start, per_page] || [],
				"total_count" => hits.size,
				"pages" => { "next" => next_cursor && { "starting_after" => next_cursor } }
			}
		end

		private

		def match?(contact, node)
			if node["field"]
				value = contact[node["field"]]
				case node["operator"]
				when "=" then value == node["value"]
				when "IN" then node["value"].include?(value)
				when "~" then value.to_s.include?(node["value"].to_s)
				else true
				end
			elsif node["operator"] == "AND"
				node["value"].all? { |child| match?(contact, child) }
			else
				node["value"].any? { |child| match?(contact, child) }
			end
		end
	end

	# 400 contacts: user1@acme.io .. user400@acme.io; every 10th is a lead.
	def build_contacts(count = 400)
		(1..count).map do |i|
			{
				"type" => "contact",
				"id" => "c#{i}",
				"role" => (i % 10).zero? ? "lead" : "user",
				"email" => "user#{i}@acme.io",
				"name" => i == 1 ? "Doe, \"J\"" : nil,
				"created_at" => 1_734_537_437,
				"location" => { "type" => "location", "country" => "Georgia", "city" => "Tbilisi" },
				"custom_attributes" => i.even? ? { "plan" => "pro", "meta" => { "a" => 1 } } : {},
				"tags" => { "type" => "list", "data" => [{ "type" => "tag", "id" => "7" }, { "type" => "tag", "id" => "9" }] },
				"notes" => { "type" => "list", "data" => [], "total_count" => 3 },
				"social_profiles" => { "type" => "list", "data" => [{ "name" => "twitter", "url" => "https://t/x" }] }
			}
		end
	end

	def setup_stack(contacts = build_contacts)
		@out = StringIO.new
		@api = FakeContactsAPI.new(contacts)
		@query_builder = Search::QueryBuilder.new
		@searcher = Services::ContactSearch.new(@api)
		@exporter = Services::SearchExporter.new(@searcher, out: @out)
		@runner = Services::SearchExportRunner.new(@query_builder, @searcher, @exporter, out: @out)
	end
end
