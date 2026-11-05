module IntercomBulkCleaner
	module Services
		# Turns a nested Intercom contact object into a flat row for CSV.
		
		# flat CSV row.
		class ContactFlattener
			DEFAULT_COLUMNS = %w[
				id external_id role email name phone email_domain email_verified owner_id
				created_at updated_at signed_up_at last_seen_at last_replied_at last_contacted_at
				last_email_opened_at last_email_clicked_at
				unsubscribed_from_emails has_hard_bounced marked_email_as_spam
				location_country location_region location_city
				browser os language_override tag_ids company_ids
			].freeze

			LIST_ID_COLUMNS = {
				"tags" => "tag_ids",
				"companies" => "company_ids",
				"opted_in_subscription_types" => "opted_in_subscription_type_ids",
				"opted_out_subscription_types" => "opted_out_subscription_type_ids"
			}.freeze

			SEPARATOR = "|".freeze
			CUSTOM_PREFIX = "custom_attributes.".freeze

			def initialize(iso_dates: true)
				@iso_dates = iso_dates
			end

			# location.country -> location_country, tags -> tag_ids, ...
			def flatten(contact)
				row = {}

				contact.each do |key, value|
					case key
					when "type", "workspace_id"
						next
					when "location"
						(value || {}).each do |location_key, location_value|
							next if location_key == "type"

							row["location_#{location_key}"] = location_value
						end
					when "social_profiles"
						profiles = list_data(value).map { |profile| [profile["name"], profile["url"]].compact.join(":") }
						row["social_profiles"] = profiles.join(SEPARATOR)
					when "custom_attributes"
						(value || {}).each do |attribute, attribute_value|
							row["#{CUSTOM_PREFIX}#{attribute}"] = scalar(attribute_value)
						end
					when "notes"
						row["notes_count"] = value.is_a?(Hash) ? value["total_count"] : nil
					when *LIST_ID_COLUMNS.keys
						row[LIST_ID_COLUMNS[key]] = list_data(value).map { |item| item["id"] }.compact.join(SEPARATOR)
					else
						row[key] = format_value(key, value)
					end
				end

				row
			end

			# Default columns plus any custom attributes found.
			def default_columns(seen_keys)
				custom = seen_keys.select { |key| key.start_with?(CUSTOM_PREFIX) }.sort
				DEFAULT_COLUMNS + custom
			end

			private

			# Items of a nested list (tags, companies, ...).
			def list_data(value)
				value.is_a?(Hash) && value["data"].is_a?(Array) ? value["data"] : []
			end

			# Timestamps -> readable dates.
			def format_value(key, value)
				if @iso_dates && key.end_with?("_at") && value.is_a?(Integer)
					Time.at(value).utc.iso8601
				else
					scalar(value)
				end
			end

			# Nested values -> JSON text.
			def scalar(value)
				value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value
			end
		end
	end
end
