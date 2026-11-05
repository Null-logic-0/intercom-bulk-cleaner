module IntercomBulkCleaner
	class CLI
		# Help texts.
		module Help
			module_function

			# Command overview.
			def usage
				<<~USAGE
				  INTERCOM BULK CLEANER

				    Usage:
				  	  bin/intercom-cleaner                           (interactive app: menus, previews, progress)
				  	  bin/intercom-cleaner search                    (jump straight to the guided search)
				  	  bin/intercom-cleaner search-export [options]   (see --help)
				  	  bin/intercom-cleaner export-all [options]      (all contacts; same output options)
				  	  bin/intercom-cleaner delete FILE [--dry-run]   (any export with contact IDs; see --help)
				  	  bin/intercom-cleaner verify FILE               (check the contacts in FILE are gone)

				    Test helpers (only for trying out bulk delete with fake contacts):
				  	  bin/intercom-cleaner create-test
				  	  bin/intercom-cleaner export
				  	  bin/intercom-cleaner delete --test-run
				USAGE
			end

			# search-export --help: operators, fields, examples.
			def search
				builder = Search::QueryBuilder
				<<~HELP

				  Operators (put spaces around them):
				#{operators}
				    IN / NIN take a comma-separated list: "email_domain IN gmail.com,yahoo.com"

				  Fields:
				#{fields}

				  Date fields only take = (on), < (before) and > (after), matched by calendar day
				  in your workspace's timezone:
				    created_at = 2026-01-15   created on that day
				    created_at < 2026-01-15   created before that day
				    created_at > 2026-01-15   created from 2026-01-16 onwards
				  Values can be YYYY-MM-DD, a Unix timestamp, or Nd for "N days ago".
				  tag_id only takes = and !=. Max #{builder::MAX_FILTERS_PER_GROUP} filters per group, #{builder::MAX_NESTING} levels of nesting.

				  Bulk search sends the list in batches of "email IN [...]" and writes the
				  values nothing matched to <output>_not_found.txt.

				  Examples:
				    bin/intercom-cleaner search                                    guided menu
				    bin/intercom-cleaner search-export -E emails.csv --role all     bulk lookup from a file
				    bin/intercom-cleaner search-export -e a@x.com,b@y.com -f "last_seen_at < 90d"
				    bin/intercom-cleaner export-all                                every user to CSV
				    bin/intercom-cleaner search-export -f "email_domain = gmail.com" -f "last_seen_at < 90d"
				    bin/intercom-cleaner search-export -f "created_at > 2026-01-01" -f "custom_attributes.plan = pro" --format json
				    bin/intercom-cleaner search-export -f "email ~ test" -f "email ~ example" --match any --count
				    bin/intercom-cleaner search-export -q examples/search_query.json --columns id,email,name,created_at
				HELP
			end

			# Operators and their words, three per line.
			def operators
				Search::Labels::OPERATOR_LABELS
					.map { |op, words| "#{op.ljust(4)}#{words}".ljust(26) }
					.each_slice(3).map { |row| "    #{row.join.rstrip}" }.join("\n")
			end

			# Fields by group, with their type.
			def fields
				builder = Search::QueryBuilder.new
				groups = Search::Labels::FIELD_GROUPS.merge("other" => Search::Labels.other_fields)

				lines = groups.map do |group, names|
					types = names.map { |name| Search::Labels.type_name(builder.field_type(name)) }
					if types.uniq.size == 1
						wrap(names, "    #{"#{group} (#{types.first})".ljust(26)}", " " * 30)
					else
						wrap(names.zip(types).map { |name, type| "#{name} (#{type})" }, "    #{group.ljust(26)}", " " * 30)
					end
				end

				(lines << "    #{'custom'.ljust(26)}custom_attributes.<name>").join("\n")
			end

			# Comma list after a label, wrapped at whole items.
			def wrap(items, label, indent, width: 100)
				lines = [label.dup]
				items.each_with_index do |item, index|
					piece = index == items.size - 1 ? item : "#{item},"
					lines << indent.dup if lines.last.length + piece.length + 1 > width && lines.last.length > label.length
					lines.last << " " unless lines.last.end_with?(" ")
					lines.last << piece
				end
				lines.join("\n")
			end
		end
	end
end
