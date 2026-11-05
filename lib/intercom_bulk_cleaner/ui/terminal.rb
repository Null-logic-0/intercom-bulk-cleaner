require 'io/console'

require_relative 'terminal/output'
require_relative 'terminal/prompts'
require_relative 'terminal/menu'
require_relative 'terminal/activity'
require_relative 'terminal/progress'

module IntercomBulkCleaner
  module UI
    # Terminal UI with no extra gems. Parts live in terminal/.
    # Not a real terminal (pipes, tests)? Plain numbered menus.
    class Terminal
      include Output
      include Prompts
      include Menu
      include Activity

      attr_reader :output

      def initialize(input: $stdin, output: $stdout, interactive: nil, color: nil)
        @input = input
        @output = output
        @interactive = interactive.nil? ? tty?(input) && tty?(output) : interactive
        @color = color.nil? ? tty?(output) && ENV['NO_COLOR'].to_s.empty? : color
      end

      def interactive?
        @interactive
      end

      private

      def tty?(io)
        io.respond_to?(:tty?) && io.tty?
      end
    end
  end
end
