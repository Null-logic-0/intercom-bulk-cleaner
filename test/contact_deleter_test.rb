require_relative "test_helper"

class ContactDeleterTest < Minitest::Test
	include TestSupport

	class FakeDeleteAPI
		attr_reader :batches

		def initialize(fail_on: nil)
			@batches = []
			@fail_on = fail_on
		end

		def delete_bulk(ids)
			@batches << ids
			raise IntercomBulkCleaner::APIError.new(500, "boom") if @fail_on == @batches.size

			{ "id" => "job#{@batches.size}" }
		end
	end

	class FakeWaiter
		def call(_job_id) = { "state" => "completed" }
	end

	class FakeVerifier
		attr_reader :verified

		def call(ids) = @verified = ids
	end

	class FakeRunRepository
		def initialize(prefix) = @prefix = prefix
		def load = @prefix || raise(IntercomBulkCleaner::ValidationError, "No test run found. Run create-test first.")
	end

	def setup
		@dir = Dir.mktmpdir
		@api = FakeDeleteAPI.new
		@verifier = FakeVerifier.new
		@out = StringIO.new
	end

	def teardown
		FileUtils.remove_entry(@dir)
	end

	def deleter(answer: nil, prefix: nil, api: @api)
		Services::ContactDeleter.new(
			api, FakeWaiter.new, FakeRunRepository.new(prefix), Validators::DeletionValidator.new, @verifier,
			batch_size: 2, default_test_file: File.join(@dir, "test.csv"), log_dir: File.join(@dir, "logs"),
			input: StringIO.new(answer.to_s + "\n"), out: @out
		)
	end

	def write_csv(name, rows, headers = %w[id external_id role email])
		path = File.join(@dir, name)
		CSV.open(path, "w") do |csv|
			csv << headers
			rows.each { |row| csv << row }
		end
		path
	end

	def search_export_csv
		write_csv("search.csv", [
			["aaa111", nil, "user", "a@x.io"],
			["bbb222", nil, "lead", "b@x.io"],
			["ccc333", "ext-3", "user", "c@x.io"],
			["aaa111", nil, "user", "a@x.io"]
		])
	end

	def test_does_not_need_create_test
		path = search_export_csv
		assert_equal 3, deleter(answer: "DELETE 3 CONTACTS").call(path: path)
		assert_equal [%w[aaa111 bbb222], %w[ccc333]], @api.batches
		assert_equal %w[aaa111 bbb222 ccc333], @verifier.verified
		assert_includes @out.string, "Duplicates ignored: 1"
		assert_includes @out.string, "Roles:     user 3, lead 1"

		log = Dir[File.join(@dir, "logs", "deleted_*.csv")].first
		assert_equal %w[aaa111 bbb222 ccc333], CSV.read(log, headers: true).map { |row| row["id"] }
	end

	def test_dry_run_and_wrong_phrase_delete_nothing
		path = search_export_csv
		assert_equal 0, deleter.call(path: path, dry_run: true)
		assert_equal 0, deleter(answer: "DELETE USERS").call(path: path)
		assert_empty @api.batches
		assert_includes @out.string, "Deletion cancelled"
		refute Dir.exist?(File.join(@dir, "logs"))
	end

	def test_reads_json_and_jsonl_exports
		contacts = [{ "id" => "x1", "email" => "x1@x.io", "role" => "user", "location" => {} }, { "id" => "x2", "role" => "lead" }]
		File.write(File.join(@dir, "a.json"), JSON.generate(contacts))
		File.write(File.join(@dir, "a.jsonl"), contacts.map { |c| JSON.generate(c) }.join("\n") + "\n")

		assert_equal 2, deleter(answer: "DELETE 2 CONTACTS").call(path: File.join(@dir, "a.json"), verify: false)
		assert_equal 2, deleter(answer: "DELETE 2 CONTACTS").call(path: File.join(@dir, "a.jsonl"), verify: false)
	end

	def test_rejects_bad_files
		assert_raises(ValidationError) { deleter.call }
		assert_raises(ValidationError) { deleter.call(path: File.join(@dir, "missing.csv")) }

		no_id = write_csv("no_id.csv", [["a@x.io"]], %w[email])
		assert_match(/needs an "id" column/, assert_raises(ValidationError) { deleter.call(path: no_id) }.message)

		emails = write_csv("emails.csv", [["a@x.io"]], %w[id])
		assert_match(/looks like an email/, assert_raises(ValidationError) { deleter.call(path: emails) }.message)
		assert_empty @api.batches
	end

	def test_test_run_mode_keeps_prefix_check
		prefix = "bulk-cleaner-test-1"
		good = write_csv("test.csv", [["id1", "#{prefix}-1", "user", "t1@x.io"], ["id2", "#{prefix}-2", "user", "t2@x.io"]])
		assert_equal 2, deleter(answer: "DELETE 2 CONTACTS", prefix: prefix).call(test_run: true)

		search_export_csv
		error = assert_raises(ValidationError) { deleter(prefix: prefix).call(path: File.join(@dir, "search.csv"), test_run: true) }
		assert_match(/outside test run/, error.message)

		assert_raises(ValidationError) { deleter(prefix: nil).call(path: good, test_run: true) }
	end

	def test_reports_progress_when_a_batch_fails
		api = FakeDeleteAPI.new(fail_on: 2)
		_stdout, stderr = capture_io do
			assert_raises(APIError) { deleter(answer: "DELETE 3 CONTACTS", api: api).call(path: search_export_csv) }
		end
		assert_match(%r{stopped on batch 2/2\. Batches 1-1 finished}, stderr)
	end
end

class DeletionVerifierTest < Minitest::Test
	class FakeFindAPI
		def initialize(existing) = @existing = existing

		def find(id)
			return { "id" => id } if @existing.include?(id)

			raise IntercomBulkCleaner::APIError.new(404, "not found")
		end
	end

	def test_passes_when_all_return_404
		verifier = IntercomBulkCleaner::Services::DeletionVerifier.new(FakeFindAPI.new([]))
		out, = capture_io { verifier.call(%w[a b c]) }
		assert_includes out, "Deleted: 3; still existing: 0"
	end

	def test_fails_when_a_contact_still_exists
		verifier = IntercomBulkCleaner::Services::DeletionVerifier.new(FakeFindAPI.new(["b"]))
		capture_io do
			assert_raises(IntercomBulkCleaner::JobError) { verifier.call(%w[a b c]) }
		end
	end
end
