module IntercomBulkCleaner
	class CLI
		# Builds the objects commands need, on first use.
		# So "help" works without a token.
		class Dependencies
			def initialize(configuration = nil)
				@configuration = configuration
			end

			def configuration
				@configuration ||= Configuration.new
			end

			# Intercom API

			def client
				@client ||= Client.new(configuration)
			end

			def contacts_api
				@contacts_api ||= API::ContactsAPI.new(client)
			end

			def job_waiter
				@job_waiter ||= Services::JobWaiter.new(
					API::BulkJobsAPI.new(client),
					timeout: configuration.job_timeout,
					poll_interval: configuration.job_poll_interval
				)
			end

			# Search & export

			def query_builder
				@query_builder ||= Search::QueryBuilder.new
			end

			def searcher
				@searcher ||= Services::ContactSearch.new(contacts_api)
			end

			def runner
				@runner ||= Services::SearchExportRunner.new(query_builder, searcher, Services::SearchExporter.new(searcher))
			end

			# Delete & verify

			def verifier
				@verifier ||= Services::DeletionVerifier.new(contacts_api)
			end

			def deleter
				@deleter ||= Services::ContactDeleter.new(
					contacts_api,
					job_waiter,
					run_repository,
					Validators::DeletionValidator.new,
					verifier,
					batch_size: configuration.batch_size,
					default_test_file: configuration.export_path
				)
			end

			# Test tools

			def run_repository
				@run_repository ||= Repositories::RunRepository.new(configuration.run_id_path)
			end

			def creator
				@creator ||= Services::TestContactCreator.new(contacts_api, job_waiter, run_repository, count: configuration.test_count)
			end

			def test_exporter
				@test_exporter ||= Services::ContactExporter.new(
					contacts_api, run_repository, Repositories::ExportRepository.new(configuration.export_path)
				)
			end

			# Interactive app

			def app
				@app ||= App.new(
					ui: UI::Terminal.new,
					query_builder: query_builder,
					searcher: searcher,
					deleter: deleter,
					verifier: verifier,
					creator: creator,
					test_exporter: test_exporter,
					whoami: method(:whoami)
				)
			end

			# Workspace name and account email, for the app banner.
			# One try only, so a bad connection doesn't delay startup.
			def whoami
				me = client.get("/me", max_retries: 0)
				{ name: me.dig("app", "name"), email: me["email"] }
			end
		end
	end
end
