module IntercomBulkCleaner
	module Search
		# Turns filters into Intercom search queries.
		# Checks Intercom's rules first: fields, operators, limits.
		class QueryBuilder
			MAX_FILTERS_PER_GROUP = 15
			MAX_NESTING = 2

			STRING_FIELDS = %w[
				id role name avatar email email_domain phone external_id language_override
				browser browser_language os location.country location.region location.city
				ios_app_version ios_device ios_app_device ios_os_version ios_app_name ios_sdk_version
				android_app_version android_device android_app_name andoid_sdk_version
				segment_id tag_id
			].freeze
			INTEGER_FIELDS = %w[owner_id].freeze
			BOOLEAN_FIELDS = %w[unsubscribed_from_emails marked_email_as_spam has_hard_bounced].freeze
			DATE_FIELDS = %w[
				created_at signed_up_at updated_at last_seen_at last_contacted_at last_replied_at
				last_email_opened_at last_email_clicked_at ios_last_seen_at android_last_seen_at
			].freeze

			OPERATORS = {
				string: %w[= != IN NIN ~ !~ ^ $],
				integer: %w[= != IN NIN < > <= >=],
				boolean: %w[= != IN NIN],
				date: %w[= < >],
				tag: %w[= !=],
				custom: %w[= != IN NIN < > <= >= ~ !~ ^ $]
			}.freeze

			LIST_OPERATORS = %w[IN NIN].freeze
			GROUP_OPERATORS = %w[AND OR].freeze
			ROLES = %w[user lead].freeze

			# Filters -> query. Needs a filter or a role.
			def build(filters:, match: "all", role: "user")
				query = build_base(filters: filters, match: match, role: role)
				raise ValidationError, "Add at least one filter, or use --role user|lead." if query.nil?

				query
			end

			# Like build, but nil when there's nothing to filter.
			def build_base(filters:, match: "all", role: "user")
				parsed = filters.map { |expression| parse_filter(expression) }
				group_operator = match == "any" ? "OR" : "AND"
				query = parsed.empty? ? nil : { "operator" => group_operator, "value" => parsed }

				query = add_role(query, role)
				validate_node!(query, 0) if query
				query
			end
			
			# Add one more filter with AND.
			def combine(query, node)
				combined =
					if query.nil?
						node
					elsif query["operator"] == "AND" && query["value"].is_a?(Array) &&
					      query["value"].size < MAX_FILTERS_PER_GROUP
						query.merge("value" => [node] + query["value"])
					else
						{ "operator" => "AND", "value" => [node, query] }
					end

				validate_node!(combined, 0)
				combined
			end

			# Operators allowed on this field.
			def operators_for(field)
				OPERATORS.fetch(field_type(field))
			end

			# Every contact of a role. "all" = users and leads.
			def build_all(role: "user")
				query =
					if role == "all"
						{ "field" => "role", "operator" => "IN", "value" => ROLES.dup }
					elsif ROLES.include?(role)
						{ "field" => "role", "operator" => "=", "value" => role }
					else
						raise ValidationError, "Role must be user, lead or all."
					end

				validate_node!(query, 0)
				query
			end

			# Query from a JSON file, for nested AND/OR.
			def from_file(path, role: "user")
				raise ValidationError, "Query file not found: #{path}" unless File.file?(path)

				json = JSON.parse(File.read(path))
				query = json.is_a?(Hash) && json.key?("query") ? json["query"] : json
				raise ValidationError, "Query file must contain a JSON object." unless query.is_a?(Hash)

				finalize(query, role)
			rescue JSON::ParserError => error
				raise ValidationError, "Invalid JSON in #{path}: #{error.message}"
			end

			# "email ~ gmail" -> {field, operator, value}
			def parse_filter(expression)
				field, operator, raw_value = expression.to_s.strip.split(/\s+/, 3)

				if field.nil? || operator.nil?
					raise ValidationError,
					      "Invalid filter #{expression.inspect}. Use \"FIELD OPERATOR VALUE\" with spaces around the operator."
				end

				operator = operator.upcase if %w[in nin].include?(operator.downcase)
				validate_operator!(field, operator)

				raw_value = raw_value.to_s.strip
				value =
					if LIST_OPERATORS.include?(operator)
						items = unquote(raw_value).split(",").map(&:strip).reject(&:empty?)
						raise ValidationError, "#{operator} needs a comma-separated list: #{expression}" if items.empty?

						items.map { |item| coerce(field, item) }
					else
						raise ValidationError, "Missing value in filter: #{expression}" if raw_value.empty?

						unquoted = unquote(raw_value)
						# Quoted value: always text.
						if unquoted != raw_value && field_type(field) == :custom
							unquoted
						else
							coerce(field, unquoted)
						end
					end

				{ "field" => field, "operator" => operator, "value" => value }
			end

			private

			# Add the role filter, then validate.
			def finalize(query, role)
				query = add_role(query, role)
				raise ValidationError, "Add at least one filter, or use --role user|lead." if query.nil?

				validate_node!(query, 0)
				query
			end

			# Add role = user/lead to the query.
			def add_role(query, role)
				return query if role.nil? || role == "all"
				raise ValidationError, "Role must be user, lead or all." unless ROLES.include?(role)

				role_filter = { "field" => "role", "operator" => "=", "value" => role }
				return role_filter if query.nil?

				if query["operator"] == "AND" && query["value"].is_a?(Array) &&
				   query["value"].size < MAX_FILTERS_PER_GROUP
					return query.merge("value" => query["value"] + [role_filter])
				end

				{ "operator" => "AND", "value" => [query, role_filter] }
			end

			# Intercom limits: 15 filters per group, 2 levels deep.
			def validate_node!(node, depth)
				raise ValidationError, "Every query node must be a JSON object." unless node.is_a?(Hash)

				if node.key?("field")
					validate_operator!(node["field"], node["operator"])
					if LIST_OPERATORS.include?(node["operator"]) && !node["value"].is_a?(Array)
						raise ValidationError, "#{node['operator']} on #{node['field']} needs an array value."
					end
					return
				end

				unless GROUP_OPERATORS.include?(node["operator"]) && node["value"].is_a?(Array)
					raise ValidationError,
					      "Query groups need \"operator\": \"AND\" or \"OR\" and a \"value\" array."
				end

				depth += 1
				if depth > MAX_NESTING
					raise ValidationError,
					      "Intercom allows at most #{MAX_NESTING} levels of nested groups, e.g. (A OR B) AND (C OR D)."
				end

				size = node["value"].size
				raise ValidationError, "Query groups cannot be empty." if size.zero?
				if size > MAX_FILTERS_PER_GROUP
					raise ValidationError,
					      "Intercom allows at most #{MAX_FILTERS_PER_GROUP} filters per AND/OR group (got #{size})."
				end

				node["value"].each { |child| validate_node!(child, depth) }
			end

			# Is this operator allowed on this field?
			def validate_operator!(field, operator)
				type = field_type(field)
				allowed = OPERATORS.fetch(type)
				return if allowed.include?(operator)

				raise ValidationError,
				      "Operator #{operator.inspect} is not allowed on #{field} (#{type}). Allowed: #{allowed.join(' ')}"
			end

			public

			# Field type: :string, :date, :boolean, ...
			def field_type(field)
				return :tag if field == "tag_id"
				return :custom if field.to_s.start_with?("custom_attributes.") && field.to_s.length > 18
				return :string if STRING_FIELDS.include?(field)
				return :integer if INTEGER_FIELDS.include?(field)
				return :boolean if BOOLEAN_FIELDS.include?(field)
				return :date if DATE_FIELDS.include?(field)

				raise ValidationError,
				      "Unknown search field #{field.inspect}. Run `bin/intercom-cleaner search-export --help` for the field list."
			end

			private

			# Text value -> the right type for the field.
			def coerce(field, value)
				return nil if value.casecmp?("null")

				case field_type(field)
				when :date then coerce_date(value)
				when :integer then coerce_integer(field, value)
				when :boolean then coerce_boolean(field, value)
				when :custom then coerce_custom(value)
				else
					if field == "role" && !ROLES.include?(value)
						raise ValidationError, "role must be user or lead (got #{value.inspect})."
					end
					value
				end
			end

			# YYYY-MM-DD, Unix time or 30d (30 days ago).
			# Sent as noon UTC so the day doesn't shift by timezone.
			def coerce_date(value)
				case value
				when /\A\d+\z/
					Integer(value)
				when /\A\d{4}-\d{2}-\d{2}\z/
					date = Date.iso8601(value)
					Time.utc(date.year, date.month, date.day, 12).to_i
				when /\A(\d+)d\z/
					date = (Time.now.utc - Integer(Regexp.last_match(1)) * 86_400).to_date
					Time.utc(date.year, date.month, date.day, 12).to_i
				else
					raise ValidationError,
					      "Invalid date #{value.inspect}. Use YYYY-MM-DD, a Unix timestamp, or Nd (N days ago)."
				end
			rescue Date::Error
				raise ValidationError, "Invalid date #{value.inspect}."
			end

			def coerce_integer(field, value)
				Integer(value)
			rescue ArgumentError
				raise ValidationError, "#{field} needs an integer (got #{value.inspect})."
			end

			def coerce_boolean(field, value)
				return true if value.casecmp?("true")
				return false if value.casecmp?("false")

				raise ValidationError, "#{field} needs true or false (got #{value.inspect})."
			end

			# Guess the type: true/false, number, else text.
			# Quote the value to force text.
			def coerce_custom(value)
				return true if value == "true"
				return false if value == "false"
				return Integer(value) if value.match?(/\A-?\d+\z/)
				return Float(value) if value.match?(/\A-?\d+\.\d+\z/)

				value
			end

			# Remove surrounding quotes.
			def unquote(value)
				return value[1..-2] if value.length >= 2 && value.start_with?('"') && value.end_with?('"')
				return value[1..-2] if value.length >= 2 && value.start_with?("'") && value.end_with?("'")

				value
			end
		end
	end
end
