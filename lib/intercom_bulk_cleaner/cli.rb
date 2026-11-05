require_relative "cli/dependencies"
require_relative "cli/help"
require_relative "cli/search_options"
require_relative "cli/search_export"
require_relative "cli/delete_commands"

module IntercomBulkCleaner
	# Command line entry: picks a command and runs it.
	# Commands live in cli/.
	class CLI
		include SearchExport
		include DeleteCommands

		# Command name -> method.
		COMMANDS = {
			nil => :start_app,
			"menu" => :start_app,
			"search" => :start_search,
			"search-export" => :search_export,
			"export-all" => :export_all,
			"delete" => :delete,
			"verify" => :verify,
			"create-test" => :create_test,
			"export" => :export_test_run,
			"help" => :help,
			"-h" => :help,
			"--help" => :help
		}.freeze

		def initialize(configuration = nil)
			@deps = Dependencies.new(configuration)
		end

		def run(args)
			command, *rest = args
			return unknown_command(command) unless COMMANDS.key?(command)

			send(COMMANDS[command], rest)
		rescue Error, KeyError, ArgumentError, OptionParser::ParseError => error
			fail_with(error.message)
		rescue Interrupt
			warn "\nCancelled."
			exit 130
		end

		private

		# Interactive app with the main menu.
		def start_app(_args)
			@deps.app.run
		end

		# Straight to the guided search.
		def start_search(_args)
			@deps.app.run_flow(:search_flow)
		end

		# Test tools: fake contacts.
		def create_test(_args)
			@deps.creator.call
		end

		# Test tools: export the last test run.
		def export_test_run(_args)
			@deps.test_exporter.call
		end

		def help(_args)
			puts Help.usage
		end

		def unknown_command(command)
			warn "Unknown command: #{command}"
			puts Help.usage
			exit 1
		end

		def fail_with(message)
			warn "#{UI::Terminal.new(output: $stderr).paint('ERROR:', :red, :bold)} #{message}"
			exit 1
		end
	end
end
