module IntercomBulkCleaner
  module UI
    class Terminal
      # Spinner and progress bar.
      module Activity
        SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

        # Spinner while the block runs.
        def spinner(message)
          unless @interactive
            say "#{message}..."
            return yield(->(_text) {})
          end

          current = message
          running = true
          thread = Thread.new do
            frame = 0
            while running
              @output.print "\r#{paint(SPINNER_FRAMES[frame % SPINNER_FRAMES.size], :cyan)} #{current}\e[K"
              frame += 1
              sleep 0.08
            end
          end

          begin
            yield(->(text) { current = text })
          ensure
            running = false
            thread.join
            @output.print "\r\e[K"
          end
        end

        # New progress bar.
        def progress(label, total: nil)
          Progress.new(self, label, total)
        end
      end
    end
  end
end
