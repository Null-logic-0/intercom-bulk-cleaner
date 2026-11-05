require_relative "test_helper"

class SearchExportTest < Minitest::Test
	include TestSupport

	def setup
		setup_stack
	end

	def test_paginates_and_flattens_csv
		Dir.mktmpdir do |dir|
			path = File.join(dir, "out.csv")
			query = @query_builder.build_all(role: "all")
			sort = Services::ContactSearch.parse_sort("created_at:asc")

			assert_equal 400, @exporter.call(query: query, output: path, sort: sort)
			assert_equal [nil, "150", "300"], @api.calls.map { |call| call[:starting_after] }
			assert_equal({ field: "created_at", order: "ascending" }, @api.calls.last[:sort])

			rows = CSV.read(path, headers: true)
			assert_equal 400, rows.size
			assert_equal %w[id external_id role email], rows.headers.first(4)
			assert_equal "2024-12-18T15:57:17Z", rows[0]["created_at"]
			assert_equal "Georgia", rows[0]["location_country"]
			assert_equal "7|9", rows[0]["tag_ids"]
			assert_equal "Doe, \"J\"", rows[0]["name"]
			assert_equal '{"a":1}', rows[1]["custom_attributes.meta"]
			refute File.exist?("#{path}.partial.jsonl")
		end
	end

	def test_json_jsonl_limit_and_columns
		Dir.mktmpdir do |dir|
			query = @query_builder.build_all(role: "all")

			@exporter.call(query: query, output: File.join(dir, "a.json"), format: "json", limit: 200)
			assert_equal 200, JSON.parse(File.read(File.join(dir, "a.json"))).size

			@exporter.call(query: query, output: File.join(dir, "a.jsonl"), format: "jsonl")
			assert_equal 400, File.readlines(File.join(dir, "a.jsonl")).size

			@exporter.call(query: query, output: File.join(dir, "c.csv"), columns: %w[id email])
			assert_equal %w[id email], CSV.read(File.join(dir, "c.csv")).first

			@exporter.call(query: query, output: File.join(dir, "u.csv"), all_columns: true, iso_dates: false)
			rows = CSV.read(File.join(dir, "u.csv"), headers: true)
			assert_equal "1734537437", rows[0]["created_at"]
			assert_equal "twitter:https://t/x", rows[0]["social_profiles"]
		end
	end

	def test_role_filter
		query = @query_builder.build_all(role: "lead")
		assert_equal 40, @runner.count([query])
	end

	def test_bulk_search_reports_not_found
		Dir.mktmpdir do |dir|
			emails = (1..100).map { |i| i.odd? ? "USER#{i}@ACME.IO" : "user#{i}@acme.io" } +
			         (1..20).map { |i| "ghost#{i}@nowhere.io" }
			bulk = Search::BulkValues.new("email", emails)
			queries = @runner.queries_for(base: @query_builder.build_base(filters: [], role: "user"), bulk: bulk, batch_size: 50)
			assert_equal 3, queries.size

			path = File.join(dir, "bulk.csv")
			assert_equal 90, @runner.run(queries: queries, output: path, bulk: bulk, role: "user").exported

			missing = File.readlines(File.join(dir, "bulk_not_found.txt")).map(&:strip)
			assert_equal 30, missing.size # 20 unknown emails + 10 leads
			assert_includes @out.string, "Use --role all to include leads."
		end
	end
end
