module IntercomBulkCleaner
	class App
		# Build filters
		module FilterBuilder
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
				operator = @ui.select(
					field.to_s,
					@query_builder.operators_for(field).map { |op| [Search::Labels.operator(op, date: type == :date), op, op] }
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
				choices = Search::Labels::FIELD_GROUPS.flat_map do |group, fields|
					fields.map { |field| [field, field, "#{group} · #{Search::Labels.type_name(@query_builder.field_type(field))}"] }
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
				words = Search::Labels.operator(operator, date: @query_builder.field_type(field) == :date)
				"#{@ui.paint(field, :bold)} #{words} #{@ui.paint(value, :cyan)}"
			end

			# AND or OR.
			def choose_match
				@ui.select("Contacts must match", [["ALL filters", "all", "AND"], ["ANY filter", "any", "OR"]])
			end
		end
	end
end
