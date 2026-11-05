require_relative "test_helper"

# Commands that never call Intercom: help, checks, dry runs.
class CLITest < Minitest::Test
	include TestSupport

	def setup
		@token = ENV["INTERCOM_ACCESS_TOKEN"]
		ENV["INTERCOM_ACCESS_TOKEN"] = "test-token"
		@dir = Dir.mktmpdir
	end

	def teardown
		ENV["INTERCOM_ACCESS_TOKEN"] = @token
		FileUtils.remove_entry(@dir)
	end

	def run_cli(*args)
		status = 0
		out, err = capture_io do
			CLI.new.run(args)
		rescue SystemExit => exit
			status = exit.status
		end
		[out, err, status]
	end

	def test_help_works_without_a_token
		ENV.delete("INTERCOM_ACCESS_TOKEN")
		out, _err, status = run_cli("help")
		assert_equal 0, status
		assert_includes out, "bin/intercom-cleaner search-export"
	end

	def test_unknown_command
		_out, err, status = run_cli("bogus")
		assert_equal 1, status
		assert_includes err, "Unknown command: bogus"
	end

	def test_search_export_dry_run
		out, = run_cli("search-export", "-f", "email ~ acme", "--sort", "created_at:asc", "--dry-run")
		body = JSON.parse(out)
		assert_equal "~", body["query"]["value"][0]["operator"]
		assert_equal({ "field" => "created_at", "order" => "ascending" }, body["sort"])
	end

	def test_export_all_dry_run
		out, = run_cli("export-all", "--role", "all", "--dry-run")
		assert_equal %w[user lead], JSON.parse(out)["query"]["value"]
	end

	def test_bulk_dry_run_mentions_batches
		out, = run_cli("search-export", "-e", (1..60).map { |i| "u#{i}@x.io" }.join(","), "--dry-run")
		assert_includes out, "(batch 1 of 2"
	end

	def test_search_option_checks
		{
			[] => "Add --emails",
			["--all", "-f", "email ~ a"] => "--all exports everything",
			["-f", "email ~ a", "-q", "q.json"] => "either --filter or --query-file",
			["-f", "created_at != 2026-01-01"] => "not allowed",
			["--format", "xml"] => "invalid argument"
		}.each do |args, message|
			_out, err, status = run_cli("search-export", *args)
			assert_equal 1, status, args.inspect
			assert_includes err, message
		end
	end

	def test_search_export_help
		out, _err, status = run_cli("search-export", "--help")
		assert_equal 0, status
		assert_includes out, "--emails-file"
		assert_includes out, "identity (text)"
	end

	def test_delete_dry_run_and_errors
		path = File.join(@dir, "x.csv")
		File.write(path, "id,email,role\nabc1,a@x.io,user\n")
		out, = run_cli("delete", path, "--dry-run")
		assert_includes out, "Dry run: nothing was deleted."

		_out, err, status = run_cli("delete")
		assert_equal 1, status
		assert_includes err, "Pass the file to delete"

		_out, err, = run_cli("delete", path, "other.csv")
		assert_includes err, "Pass one file"
	end

	def test_verify_usage
		out, = run_cli("verify")
		assert_includes out, "Usage: bin/intercom-cleaner verify FILE"
	end
end
