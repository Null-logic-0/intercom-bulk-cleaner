module IntercomBulkCleaner
	class App
		# Build filters: field -> condition -> value.
		module FilterBuilder
			# Fields in the picker, grouped.
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

			private

			# Ask for filters until Continue. nil = back to menu.
			def build_filters
				filters = [ask_filter]

				loop do
					@ui.say
					@ui.info("Filters:")
					filters.each_with_index { |filter, index| @ui.say "    #{index + 1}. #{describe_filter(filter)}" }

					options = []
					options << ["Add another filter", :add] if filters.size < Search::QueryBuilder::MAX_FILTERS_PER_GROUP
					options << ["Remove a filter", :remove]
					options << ["Continue", :done]
					options << ["Back to menu", :back]

					case @ui.select("Next?", options)
					when :add then filters << ask_filter
					when :remove
						index = @ui.select("Remove which filter?", filters.each_with_index.map { |filter, i| [describe_filter(filter), i] })
						filters.delete_at(index)
						filters << ask_filter if filters.empty?
					when :done then return filters
					when :back then return nil
					end
				end
			end

			# One filter: field, condition, value.
			def ask_filter
				field = choose_field
				type = @query_builder.field_type(field)
				labels = type == :date ? DATE_LABELS : OPERATOR_LABELS
				operator = @ui.select(
					field.to_s,
					@query_builder.operators_for(field).map { |op| [labels.fetch(op), op, op] }
				)

				validator = lambda do |answer|
					@query_builder.parse_filter("#{field} #{operator} #{answer}")
					nil
				rescue ValidationError => error
					error.message
				end
				value = @ui.ask(value_question(type, operator), validate: validator)

				"#{field} #{operator} #{value}"
			end

			# Pick a field. Type to search.
			def choose_field
				choices = FIELD_GROUPS.flat_map do |group, fields|
					fields.map { |field| [field, field, "#{group} · #{TYPE_NAMES.fetch(@query_builder.field_type(field))}"] }
				end
				choices << ["custom attribute...", :custom, "custom_attributes.<name>"]

				field = @ui.select("Filter on which field?", choices, filter: true)
				return field unless field == :custom

				name = @ui.ask("Custom attribute name:").sub(/\Acustom_attributes\./, "")
				"custom_attributes.#{name}"
			end

			# Value prompt with a format hint.
			def value_question(type, operator)
				return "Values (comma-separated):" if Search::QueryBuilder::LIST_OPERATORS.include?(operator)

				case type
				when :date then "Date (YYYY-MM-DD, Unix timestamp, or 30d = 30 days ago):"
				when :boolean then "Value (true or false):"
				when :integer, :tag then "Value (number):"
				else "Value:"
				end
			end

			# "email ~ x" -> "email contains x"
			def describe_filter(filter)
				field, operator, value = filter.split(/\s+/, 3)
				labels = @query_builder.field_type(field) == :date ? DATE_LABELS : OPERATOR_LABELS
				"#{@ui.paint(field, :bold)} #{labels.fetch(operator, operator)} #{@ui.paint(value, :cyan)}"
			end

			# AND or OR.
			def choose_match
				@ui.select("Contacts must match", [["ALL filters", "all", "AND"], ["ANY filter", "any", "OR"]])
			end
		end
	end
end
