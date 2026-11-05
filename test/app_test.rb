require_relative "test_helper"

class AppTest < Minitest::Test
	include TestSupport

	class FakeDeleteAPI
		attr_reader :batches

		def initialize
			@batches = []
		end

		def delete_bulk(ids)
			@batches << ids
			{ "id" => "job#{@batches.size}" }
		end
	end

	class FakeWaiter
		def call(_job_id)
			yield "running" if block_given?
			yield "completed" if block_given?
			{ "state" => "completed" }
		end
	end

	class FakeVerifier
		attr_reader :checked

		def initialize(remaining = [])
			@remaining = remaining
		end

		def check(ids)
			@checked = ids
			ids.each_index { |index| yield index + 1, ids.size }
			@remaining
		end
	end

	def setup
		setup_stack
		@dir = Dir.mktmpdir
		@exports = File.join(@dir, "exports")
		@logs = File.join(@dir, "logs")
		FileUtils.mkdir_p([@exports, @logs])
		@delete_api = FakeDeleteAPI.new
		@verifier = FakeVerifier.new
	end

	def teardown
		FileUtils.remove_entry(@dir)
	end

	def app(answers, whoami: nil)
		@screen = StringIO.new
		ui = UI::Terminal.new(input: StringIO.new(answers.join("\n") + "\n"), output: @screen, interactive: false, color: false)
		deleter = Services::ContactDeleter.new(
			@delete_api, FakeWaiter.new, nil, Validators::DeletionValidator.new, @verifier,
			batch_size: 100, default_test_file: nil, log_dir: @logs, out: StringIO.new
		)
		App.new(ui: ui, query_builder: @query_builder, searcher: @searcher, deleter: deleter, verifier: @verifier,
		        whoami: whoami, exports_dir: @exports, logs_dir: @logs)
	end

	def choice(list, value)
		(list.index(value) + 1).to_s
	end

	def test_search_flow_builds_filters_previews_and_exports
		path = File.join(@exports, "search.csv")
		contains = choice(@query_builder.operators_for("email"), "~")
		before = choice(@query_builder.operators_for("created_at"), "<")
		created_at = choice(App::FIELD_GROUPS.values.flatten, "created_at")

		app([
			"1", contains, "acme",           # email contains acme
			"1",                             # add another filter
			created_at, before, "bad", "2027-01-01",
			"3",                             # continue
			"1", "1",                        # match all, users
			"1", "1", path,                  # export, csv, path
			"2"                              # back to menu
		]).run_flow(:search_flow)

		assert_equal 360, CSV.read(path, headers: true).size
		assert_includes @screen.string, "360 contacts match"
		assert_includes @screen.string, "Invalid date"
		assert_includes @screen.string, "email contains acme"
		assert_includes @screen.string, "created_at before 2027-01-01"
		assert_includes @screen.string, "user1@acme.io"   # preview table
		assert_includes @screen.string, "Saved 360 contacts"
	end

	def test_remove_filter_and_back_to_menu
		app(["1", "1", "x@y.io", "2", "1", "1", "5", "acme", "4"]).run_flow(:search_flow)
		refute_includes @screen.string, "contacts match"
	end

	def test_bulk_flow_reports_not_found
		path = File.join(@exports, "bulk.json")
		app([
			"1", "user10@acme.io, USER11@acme.io", "ghost@x.io", "",   # paste
			"n",                                                     # no extra filters
			"3",                                                     # users and leads
			"1", "2", path,                                          # export, json
			"2"
		]).run_flow(:bulk_flow)

		assert_equal 2, JSON.parse(File.read(path)).size
		assert_includes @screen.string, "Loaded 3 unique emails"
		assert_includes @screen.string, "Matched 2 of 3 emails"
		assert_includes @screen.string, "1 not found"
	end

	def test_export_then_delete_then_verify
		path = File.join(@exports, "leads.csv")
		app([
			"2",                       # leads
			"1", "1", path,            # export csv
			"1",                       # delete these contacts
			"DELETE 40 CONTACTS",      # confirm
			"y"                        # verify
		]).run_flow(:export_all_flow)

		assert_equal 40, @delete_api.batches.flatten.size
		assert_equal 40, @verifier.checked.size
		assert_includes @screen.string, "Permanent deletion"
		assert_includes @screen.string, "Deleted 40 contacts in 1 batch"
		assert_includes @screen.string, "All 40 contacts are gone"
		assert_equal 1, Dir[File.join(@logs, "deleted_*.csv")].size
	end

	def test_delete_flow_lists_exports_and_cancels_on_wrong_phrase
		File.write(File.join(@exports, "old.csv"), "id,email,role\nabc1,a@x.io,user\n")
		app(["1", "DELETE 2 CONTACTS"]).run_flow(:delete_flow)

		assert_includes @screen.string, "old.csv"
		assert_includes @screen.string, "1 rows"
		assert_includes @screen.string, "Cancelled. Nothing was deleted."
		assert_empty @delete_api.batches
	end

	def test_verify_flow_reports_remaining
		File.write(File.join(@logs, "deleted_20260101-000000.csv"), "id,external_id,role,email\nid1,,user,a@x.io\nid2,,user,b@x.io\n")
		@verifier = FakeVerifier.new(["id2"])
		app(["1"]).run_flow(:verify_flow)

		assert_includes @screen.string, "1 of 2 contacts still exist"
		assert_includes @screen.string, "id2"
	end

	def test_errors_are_shown_not_raised
		app(["2"]).run_flow(:delete_flow) # "Enter a file path..." is choice 1 when no exports exist
	rescue Exception => error
		flunk "raised #{error.class}: #{error.message}"
	end

	def test_test_run_delete_uses_the_test_export
		prefix = "bulk-cleaner-test-1"
		runs = Repositories::RunRepository.new(File.join(@dir, "run.txt"))
		runs.save(prefix)
		test_file = File.join(@dir, "test_run.csv")
		File.write(test_file, "id,external_id,role,email\nt1,#{prefix}-1,user,t1@x.io\n")
		File.write(File.join(@exports, "other.csv"), "id\nzzz\n")

		screen = StringIO.new
		ui = UI::Terminal.new(input: StringIO.new("DELETE 1 CONTACTS\nn\n"), output: screen, interactive: false, color: false)
		deleter = Services::ContactDeleter.new(
			@delete_api, FakeWaiter.new, runs, Validators::DeletionValidator.new, @verifier,
			batch_size: 100, default_test_file: test_file, log_dir: @logs, out: StringIO.new
		)
		App.new(ui: ui, query_builder: @query_builder, searcher: @searcher, deleter: deleter, verifier: @verifier,
		        exports_dir: @exports, logs_dir: @logs).delete_flow(test_run: true)

		assert_equal [["t1"]], @delete_api.batches
		refute_includes screen.string, "other.csv"
	end

	def test_main_menu_shows_workspace_and_quits
		app([App::MENU.size.to_s], whoami: -> { { name: "Acme Inc", email: "luka@acme.io" } }).run

		assert_includes @screen.string, "Intercom Bulk Cleaner"
		assert_includes @screen.string, "Workspace: Acme Inc"
		assert_includes @screen.string, "Bye!"
	end

	def test_main_menu_survives_connection_errors
		app([App::MENU.size.to_s], whoami: -> { raise IntercomBulkCleaner::APIError.new(401, "unauthorized") }).run
		assert_includes @screen.string, "Not connected: Intercom API error 401"
	end
end
