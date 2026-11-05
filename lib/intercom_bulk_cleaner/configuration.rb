module IntercomBulkCleaner
	# Settings from .env: token, batch size, file paths.
	class Configuration
		attr_reader :access_token, :base_url, :api_version, :test_count,
		            :batch_size, :job_timeout, :job_poll_interval,
		            :export_path, :run_id_path

		def initialize
			@access_token = ENV["INTERCOM_ACCESS_TOKEN"]
			raise ConfigurationError, "Set INTERCOM_ACCESS_TOKEN first." if @access_token.nil? || @access_token.empty?

			@base_url = ENV.fetch("INTERCOM_BASE_URL", "https://api.intercom.io")
			@api_version = ENV.fetch("INTERCOM_API_VERSION", "2.17")
			@test_count = Integer(ENV.fetch("TEST_CONTACT_COUNT", "100"))
			@batch_size = Integer(ENV.fetch("BATCH_SIZE", "100"))
			@job_timeout = Integer(ENV.fetch("JOB_TIMEOUT", "600"))
			@job_poll_interval = Integer(ENV.fetch("JOB_POLL_INTERVAL", "5"))

			@export_path = ENV.fetch(
				"EXPORT_FILE",
				"exports/intercom_users_to_delete.csv"
			)
			@run_id_path = ENV.fetch("TEST_RUN_FILE", "exports/test_run_id.txt")

			raise ConfigurationError, "TEST_CONTACT_COUNT must be positive." unless @test_count.positive?
			raise ConfigurationError, "BATCH_SIZE must be between 1 and 100." unless @batch_size.between?(1, 100)
		end
	end
end
