require_relative "test_helper"

class BulkValuesTest < Minitest::Test
	include TestSupport

	def test_txt_file
		Dir.mktmpdir do |dir|
			path = File.join(dir, "emails.txt")
			File.write(path, "email\nUser1@ACME.io\nuser2@acme.io\n\nuser2@acme.io\nnot-an-email\n\"user3@acme.io\"\n")
			bulk = Search::BulkValues.from_file(path)
			assert_equal ["User1@ACME.io", "user2@acme.io", "user3@acme.io"], bulk.values
			assert_equal ["not-an-email"], bulk.skipped
		end
	end

	def test_csv_file_uses_email_column
		Dir.mktmpdir do |dir|
			path = File.join(dir, "emails.csv")
			File.write(path, "﻿Name,Email,Plan\nA,user5@acme.io,pro\nB,USER6@acme.io,free\n")
			bulk = Search::BulkValues.from_file(path)
			assert_equal ["user5@acme.io", "USER6@acme.io"], bulk.values
			assert_equal [["user5@acme.io", "USER6@acme.io", "user6@acme.io"]], bulk.batches(50)
		end
	end

	def test_pasted_text_and_batching
		bulk = Search::BulkValues.from_text("a@x.io, b@x.io;c@x.io\nd@x.io mailto:e@x.io")
		assert_equal 5, bulk.size
		assert_equal [2, 2, 1], bulk.batches(2).map { |batch| batch.size }
	end

	def test_ids_keep_case_and_empty_list_fails
		assert_equal [["AbC"]], Search::BulkValues.new("id", ["AbC"]).batches
		assert_raises(ValidationError) { Search::BulkValues.new("email", ["nope"]) }
	end
end
