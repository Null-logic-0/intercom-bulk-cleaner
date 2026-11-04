module IntercomBulkCleaner
	class CLI
		def initialize(configuration = Configuration.new)
			client = Client.new(configuration)
			contacts_api = API::ContactsAPI.new(client)
			jobs_api = API::BulkJobsAPI.new(client)

			job_waiter = Services::JobWaiter.new(
				jobs_api,
				timeout: configuration.job_timeout,
				poll_interval: configuration.job_poll_interval
			)

			run_repository = Repositories::RunRepository.new(configuration.run_id_path)
			export_repository = Repositories::ExportRepository.new(configuration.export_path)

			@creator = Services::TestContactCreator.new(
				contacts_api, job_waiter, run_repository,
				count: configuration.test_count
			)

			@exporter = Services::ContactExporter.new(
				contacts_api, run_repository, export_repository,
				expected_count: configuration.test_count
			)

			@deleter = Services::ContactDeleter.new(
				contacts_api,
				job_waiter,
				export_repository,
				run_repository,
				Validators::DeletionValidator.new(expected_count: configuration.test_count),
				Services::DeletionVerifier.new(contacts_api),
				batch_size: configuration.batch_size
			)
		end

		def run(args)
			case args[0]
			when "create-test"
				@creator.call
			when "export"
				@exporter.call
			when "delete"
				@deleter.call
			else
				print_usage
			end
		rescue Error, KeyError, ArgumentError => error
			warn "ERROR: #{error.message}"
			exit 1
		end

		private

		def print_usage
			puts <<~USAGE
			  INTERCOM BULK CLEANER

			  Usage:
			    bin/intercom-cleaner create-test
			    bin/intercom-cleaner export
			    bin/intercom-cleaner delete
			USAGE
		end
	end
end
