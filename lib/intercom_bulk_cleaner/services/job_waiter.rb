module IntercomBulkCleaner
	module Services
		class JobWaiter
			def initialize(jobs_api, timeout:, poll_interval:)
				@jobs_api = jobs_api
				@timeout = timeout
				@poll_interval = poll_interval
			end

			def call(job_id)
				started_at = Time.now

				loop do
					if Time.now - started_at > @timeout
						raise JobError, "Job #{job_id} timed out after #{@timeout} seconds."
					end

					sleep @poll_interval
					response = @jobs_api.find(job_id)
					state = response.fetch("state")

					puts "Job #{job_id}: #{state}"

					case state
					when "pending", "running"
						next
					when "completed"
						return response
					when "completed_with_errors"
						warn JSON.pretty_generate(response["tasks"])
						raise JobError, "Bulk job #{job_id} completed with errors."
					else
						raise JobError, "Unexpected job state: #{state.inspect}"
					end
				end
			end
		end
	end
end
