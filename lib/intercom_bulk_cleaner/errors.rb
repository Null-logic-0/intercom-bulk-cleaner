module IntercomBulkCleaner
	# Base error. Shown to the user as a short message.
	class Error < StandardError; end

	class ConfigurationError < Error; end

	class ValidationError < Error; end

	class JobError < Error; end

	# Intercom answered with an error status.
	class APIError < Error
		attr_reader :status, :body

		def initialize(status, body)
			@status = status
			@body = body
			super("Intercom API error #{status}: #{body}")
		end
	end
end
