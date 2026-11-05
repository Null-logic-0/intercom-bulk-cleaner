module IntercomBulkCleaner
  module UI
    class Terminal
      # One-line progress bar: bar and %, or just a count.
      class Progress
        WIDTH = 24

        def initialize(terminal, label, total)
          @terminal = terminal
          @label = label
          @total = total
          @current = 0
          @detail = nil
        end

        # Redraw with new numbers.
        def update(current, total: @total, detail: @detail)
          @current = current
          @total = total
          @detail = detail
          return unless @terminal.interactive?

          @terminal.output.print "\r  #{render}\e[K"
        end

        # Clear the line.
        def finish
          @terminal.output.print "\r\e[K" if @terminal.interactive?
        end

        private

        # The bar text.
        def render
          count = @terminal.number(@current)
          detail = @detail ? @terminal.paint("  #{@detail}", :gray) : ''

          if @total.to_i.positive?
            ratio = [@current.to_f / @total, 1.0].min
            filled = (ratio * WIDTH).round
            bar = @terminal.paint('█' * filled, :cyan) + @terminal.paint('░' * (WIDTH - filled), :gray)
            "#{@label} #{bar} #{(ratio * 100).round.to_s.rjust(3)}%  #{count}/#{@terminal.number(@total)}#{detail}"
          else
            "#{@label} #{count}#{detail}"
          end
        end
      end
    end
  end
end
