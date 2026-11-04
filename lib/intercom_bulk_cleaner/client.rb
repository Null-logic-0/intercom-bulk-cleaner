module IntercomBulkCleaner
	class Client
		MAX_RETRIES = 6

		def initialize(configuration)
			@configuration = configuration
		end

		def get(path, params = {})
			request(:get, path, params: params)
		end

		def post(path, body = {})
			request(:post, path, body: body)
		end

		private

		def request(method, path, params: {}, body: nil)
			uri = URI.join(
				ensure_trailing_slash(@configuration.base_url),
				path.sub(%r{\A/}, "")
			)
			uri.query = URI.encode_www_form(params) unless params.empty?

			retries = 0

			begin
				request_class = method == :get ? Net::HTTP::Get : Net::HTTP::Post
				http_request = request_class.new(uri)
				http_request["Authorization"] = "Bearer #{@configuration.access_token}"
				http_request["Accept"] = "application/json"
				http_request["Content-Type"] = "application/json"
				http_request["Intercom-Version"] = @configuration.api_version
				http_request.body = JSON.generate(body) unless body.nil?

				response = Net::HTTP.start(
					uri.host,
					uri.port,
					use_ssl: uri.scheme == "https",
					open_timeout: 15,
					read_timeout: 60
				) { |http| http.request(http_request) }

				status = response.code.to_i
				if status == 429 || status >= 500
					error = APIError.new(status, response.body)
					raise error
				end

				unless response.is_a?(Net::HTTPSuccess)
					raise APIError.new(status, response.body)
				end

				return {} if response.body.nil? || response.body.empty?

				JSON.parse(response.body)
			rescue APIError => error
				# A 5xx error doesn't mean the request failed.
				# Retrying could create duplicate contacts or jobs.
				retryable = error.status == 429 || (method == :get && error.status >= 500)
				retries += 1
				raise unless retryable && retries <= MAX_RETRIES

				delay = retry_delay(response, retries)
				warn "#{error.message}; retrying in #{delay}s"
				sleep(delay)
				retry
			rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, EOFError,
				IOError, SystemCallError => error
				# A network error doesn't mean Intercom rejected the request.
				# Retrying could create duplicates.
				raise if method == :post

				retries += 1
				raise if retries > MAX_RETRIES

				delay = [2 ** retries, 60].min
				warn "Network error: #{error.message}; retrying in #{delay}s"
				sleep(delay)
				retry
			end
		end

		def retry_delay(response, retries)
			retry_after = response && response["Retry-After"]
			parsed = Integer(retry_after, exception: false)
			parsed&.positive? ? [parsed, 120].min : [2 ** retries, 60].min
		end

		def ensure_trailing_slash(url)
			url.end_with?("/") ? url : "#{url}/"
		end
	end
end
