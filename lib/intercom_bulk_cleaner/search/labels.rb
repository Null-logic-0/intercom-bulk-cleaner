module IntercomBulkCleaner
	module Search
		# Words people see for fields and operators.
		# Shared by the app and search-export --help.
		module Labels
			# Fields grouped by topic.
			FIELD_GROUPS = {
				"identity" => %w[email name email_domain external_id id phone role],
				"activity" => %w[
					created_at signed_up_at last_seen_at last_contacted_at last_replied_at updated_at
					last_email_opened_at last_email_clicked_at
				],
				"email status" => %w[unsubscribed_from_emails has_hard_bounced marked_email_as_spam],
				"organisation" => %w[tag_id segment_id owner_id],
				"location & device" => %w[location.country location.region location.city browser browser_language os language_override]
			}.freeze

			# Field types in plain words.
			TYPE_NAMES = {
				string: "text", integer: "number", boolean: "true/false", date: "date", tag: "tag ID", custom: "custom"
			}.freeze

			# Operators in plain words.
			OPERATOR_LABELS = {
				"=" => "is", "!=" => "is not", "IN" => "is any of", "NIN" => "is none of",
				"~" => "contains", "!~" => "does not contain", "^" => "starts with", "$" => "ends with",
				"<" => "is less than", ">" => "is greater than", "<=" => "is at most", ">=" => "is at least"
			}.freeze

			# Date operators in plain words.
			DATE_LABELS = { "=" => "on", "<" => "before", ">" => "after" }.freeze

			module_function

			# Operator in words. Dates say on / before / after.
			def operator(op, date: false)
				(date ? DATE_LABELS : OPERATOR_LABELS).fetch(op, op)
			end

			# :date -> "date", :boolean -> "true/false"
			def type_name(type)
				TYPE_NAMES.fetch(type, type.to_s)
			end

			# Searchable fields in no group (mobile app fields, avatar).
			def other_fields
				all = QueryBuilder::STRING_FIELDS + QueryBuilder::INTEGER_FIELDS +
				      QueryBuilder::BOOLEAN_FIELDS + QueryBuilder::DATE_FIELDS
				all - FIELD_GROUPS.values.flatten
			end
		end
	end
end
