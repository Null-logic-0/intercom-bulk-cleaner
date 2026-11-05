require_relative "test_helper"

class QueryBuilderTest < Minitest::Test
	include TestSupport

	def setup
		@builder = Search::QueryBuilder.new
	end

	def test_builds_and_group_with_role
		query = @builder.build(filters: ["email_domain IN gmail.com, yahoo.com", "owner_id = 42"])
		assert_equal "AND", query["operator"]
		assert_equal %w[gmail.com yahoo.com], query["value"][0]["value"]
		assert_equal 42, query["value"][1]["value"]
		assert_equal({ "field" => "role", "operator" => "=", "value" => "user" }, query["value"].last)
	end

	def test_coerces_values
		query = @builder.build(filters: ["has_hard_bounced = false", 'custom_attributes.code = "123"', "custom_attributes.seats >= 5"], role: "all")
		assert_equal [false, "123", 5], query["value"].map { |filter| filter["value"] }
	end

	def test_dates_become_noon_utc
		query = @builder.build(filters: ["created_at > 2026-01-15"], role: "all")
		assert_equal Time.utc(2026, 1, 15, 12).to_i, query["value"][0]["value"]
		assert_kind_of Integer, @builder.build(filters: ["last_seen_at < 90d"], role: "all")["value"][0]["value"]
	end

	def test_match_any_is_wrapped_with_role
		query = @builder.build(filters: ["email ~ a", "email ~ b"], match: "any")
		assert_equal "AND", query["operator"]
		assert_equal "OR", query["value"][0]["operator"]
	end

	def test_build_all
		assert_equal({ "field" => "role", "operator" => "=", "value" => "user" }, @builder.build_all)
		assert_equal %w[user lead], @builder.build_all(role: "all")["value"]
	end

	def test_combine_keeps_nesting_within_limits
		base = @builder.build_base(filters: ["email ~ a", "email ~ b"], match: "any", role: "user")
		combined = @builder.combine(base, { "field" => "email", "operator" => "IN", "value" => ["x@y.io"] })
		assert_equal "IN", combined["value"][0]["operator"]
		assert_nil @builder.build_base(filters: [], role: "all")
	end

	def test_rejects_what_intercom_rejects
		{
			"created_at != 2026-01-01" => /not allowed/,
			"tag_id IN 1,2" => /not allowed/,
			"foo = 1" => /Unknown search field/,
			"created_at < yesterday" => /Invalid date/,
			"role = admin" => /role must be/
		}.each do |filter, message|
			error = assert_raises(ValidationError) { @builder.build(filters: [filter]) }
			assert_match message, error.message
		end

		error = assert_raises(ValidationError) { @builder.build(filters: Array.new(16) { |i| "email ~ x#{i}" }, role: "all") }
		assert_match(/15/, error.message)
	end

	def test_query_file_and_nesting_limit
		query = @builder.from_file(File.expand_path("../examples/search_query.json", __dir__))
		assert_equal 4, query["value"].size

		Dir.mktmpdir do |dir|
			path = File.join(dir, "deep.json")
			deep = { operator: "AND", value: [{ operator: "OR", value: [{ operator: "AND", value: [{ field: "email", operator: "=", value: "x" }] }] }] }
			File.write(path, JSON.generate(deep))
			assert_raises(ValidationError) { @builder.from_file(path, role: "all") }
		end
	end
end
