module IntercomBulkCleaner
  module UI
    class Terminal
      # Text questions.
      module Prompts
        # Ask until the answer is valid.
        def ask(question, default: nil, required: true, validate: nil)
          loop do
            suffix = default.nil? ? '' : paint(" (#{default})", :gray)
            @output.print "#{paint('?', :green)} #{paint(question, :bold)}#{suffix} "
            answer = read_line.strip
            answer = default.to_s if answer.empty? && !default.nil?

            problem = required && answer.empty? ? 'Please enter a value.' : nil
            problem ||= validate&.call(answer) unless answer.empty?
            return answer unless problem

            error(problem)
          end
        end

        # y/n question.
        def yes?(question, default: false)
          answer = ask("#{question} #{paint(default ? '[Y/n]' : '[y/N]', :gray)}", required: false)
          answer.empty? ? default : answer.downcase.start_with?('y')
        end

        # Read lines until an empty one.
        def multiline(question)
          say "#{paint('?', :green)} #{paint(question, :bold)} #{paint('(finish with an empty line)', :gray)}"
          lines = []
          loop do
            line = read_line
            break if line.strip.empty?

            lines << line
          end
          lines.join("\n")
        end

        private

        # One line. Error if input is closed.
        def read_line
          line = @input.gets
          raise Error, 'Input closed.' if line.nil?

          line.chomp
        end
      end
    end
  end
end
