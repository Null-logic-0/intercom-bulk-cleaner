require_relative "app/file_picker"
require_relative "app/filter_builder"
require_relative "app/search_flows"
require_relative "app/delete_flows"

module IntercomBulkCleaner
	# Interactive app: bin/intercom-cleaner
	# Main menu and loop here. Flows live in app/.
	class App
		include FilePicker
		include FilterBuilder
		include SearchFlows
		include DeleteFlows

		MENU = [
			["Search & export", :search_flow, "filter by email, dates, tags, custom attributes..."],
			["Bulk lookup by email", :bulk_flow, "paste a list or load a .txt / .csv"],
			["Export all contacts", :export_all_flow, "every user and/or lead"],
			["Delete contacts from a file", :delete_flow, "preview, confirm, delete, verify"],
			["Verify a past deletion", :verify_flow, "check deleted contacts are gone"],
			["Test tools", :test_tools_flow, "create and remove fake contacts"],
			["Quit", :quit]
		].freeze

		PREVIEW_ROWS = 8

		def initialize(ui:, query_builder:, searcher:, deleter:, verifier:, whoami: nil,
		               creator: nil, test_exporter: nil, exports_dir: "exports", logs_dir: "logs")
			@ui = ui
			@query_builder = query_builder
			@searcher = searcher
			@deleter = deleter
			@verifier = verifier
			@whoami = whoami
			@creator = creator
			@test_exporter = test_exporter
			@exports_dir = exports_dir
			@logs_dir = logs_dir

			silent = StringIO.new
			@runner = Services::SearchExportRunner.new(
				query_builder, searcher, Services::SearchExporter.new(searcher, out: silent), out: silent
			)
		end

		# Show the menu until Quit.
		def run
			banner

			loop do
				choice =
					begin
						@ui.select("What do you want to do?", MENU)
					rescue Interrupt
						:quit
					end
				break if choice == :quit

				run_flow(choice)
				@ui.say
			end

			@ui.muted("Bye!")
		end

		# Run one flow. Show errors instead of crashing.
		def run_flow(name)
			send(name)
		rescue Interrupt
			@ui.say
			@ui.warning("Cancelled.")
		rescue Error => error
			@ui.error(error.message)
		end

		private

		# Title box with the connected workspace.
		def banner
			lines = [@ui.paint("Search, export and bulk delete Intercom contacts", :gray)]
			lines << workspace_line
			@ui.say
			@ui.box("Intercom Bulk Cleaner", lines)
		end

		# Which Intercom workspace we're connected to.
		def workspace_line
			return @ui.paint("Workspace: unknown", :gray) unless @whoami

			info = @ui.spinner("Connecting to Intercom") { @whoami.call }
			@workspace_name = info[:name]
			"Workspace: #{@ui.paint(info[:name] || 'unknown', :bold)}#{info[:email] ? @ui.paint("  ·  #{info[:email]}", :gray) : ''}"
		rescue StandardError => error # any failure here just means "not connected"
			@ui.paint("Not connected: #{error.message[0, 60]}", :red)
		end

		def workspace_name
			@workspace_name
		end
	end
end
