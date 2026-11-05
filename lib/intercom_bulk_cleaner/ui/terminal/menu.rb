module IntercomBulkCleaner
  module UI
    class Terminal
      # Pick from a list: arrow keys in a terminal, numbers otherwise.
      module Menu
        PAGE_SIZE = 10

        # choices: "text" or [label, value, detail]
        # filter: true = type to search
        def select(question, choices, filter: false)
          items = choices.map do |choice|
            choice.is_a?(Array) ? [choice[0].to_s, choice[1], choice[2]] : [choice.to_s, choice, nil]
          end
          raise ArgumentError, 'Nothing to choose from.' if items.empty?

          @interactive ? select_interactive(question, items, filter) : select_numbered(question, items)
        end

        private

        # Plain numbered list.
        def select_numbered(question, items)
          say paint(question, :bold)
          items.each_with_index do |(label, _value, detail), index|
            say "  #{index + 1}. #{label}#{detail ? paint("  #{detail}", :gray) : ''}"
          end

          loop do
            @output.print "Choose 1-#{items.size}: "
            number = Integer(read_line.strip, exception: false)
            return items[number - 1][1] if number&.between?(1, items.size)

            say "  Enter a number between 1 and #{items.size}."
          end
        end

        # Arrow-key list, redrawn on every key.
        def select_interactive(question, items, filter)
          query = +''
          index = 0
          offset = 0
          drawn = 0
          hint = filter ? 'type to filter, ↑/↓, enter' : '↑/↓, enter'
          @output.print "\e[?25l"

          loop do
            visible = filter && !query.empty? ? items.select { |item| matches?(item, query) } : items
            index = index.clamp(0, [visible.size - 1, 0].max)
            offset = index if index < offset
            offset = index - PAGE_SIZE + 1 if index >= offset + PAGE_SIZE

            status = filter && !query.empty? ? paint("filter: #{query}", :yellow) : paint(hint, :gray)
            lines = ["#{paint('?', :green)} #{paint(question, :bold)} #{status}"]
            if visible.empty?
              lines << paint('  no matches', :gray)
            else
              page = visible[offset, PAGE_SIZE]
              label_width = page.map { |item| item[0].length }.max
              page.each_with_index do |item, row|
                lines << render_item(item, offset + row == index, label_width)
              end
              lines << paint("  (#{index + 1}/#{visible.size})", :gray) if visible.size > PAGE_SIZE
            end

            redraw(lines, drawn)
            drawn = lines.size

            case (key = read_key)
            when :up then index = (index - 1) % [visible.size, 1].max
            when :down then index = (index + 1) % [visible.size, 1].max
            when :interrupt then raise Interrupt
            when :backspace then query.chop! if filter
            when :escape then query.clear if filter
            when :enter
              next if visible.empty?

              label, value, = visible[index]
              redraw(["#{paint('?', :green)} #{paint(question, :bold)} #{paint(label, :cyan)}"], drawn)
              return value
            when String
              if filter && key.match?(/\A[[:print:]]\z/)
                query << key
                index = 0
              end
            end
          end
        ensure
          @output.print "\e[?25h"
        end

        # One row: marker, label, gray detail.
        def render_item(item, selected, label_width)
          label, _value, detail = item
          room = terminal_width - 6
          label = truncate(label, room)
          padded = detail ? label.ljust([label_width, room].min) : label
          detail = detail && room - padded.length > 6 ? truncate(detail, room - padded.length - 2) : nil
          detail_text = detail ? paint("  #{detail}", :gray) : ''
          text = selected ? paint(padded, :cyan, :bold) : padded

          "#{selected ? paint('›', :cyan) : ' '} #{text}#{detail_text}"
        end

        # Does the item match what was typed?
        def matches?(item, query)
          "#{item[0]} #{item[2]}".downcase.include?(query.downcase)
        end

        # Replace the previous drawing.
        def redraw(lines, previous)
          @output.print "\e[#{previous}A" if previous.positive?
          @output.print "\r\e[J"
          @output.print lines.join("\n") + "\n"
        end

        # One key press -> :up, :down, :enter, ...
        def read_key
          char = @input.getch
          case char
          when "\r", "\n" then :enter
          when "\u0003" then :interrupt
          when "\u007F", "\b" then :backspace
          when "\e"
            case read_escape_sequence
            when '[A', 'OA' then :up
            when '[B', 'OB' then :down
            when '' then :escape
            else :unknown
            end
          else char
          end
        end

        # Rest of an arrow-key code.
        def read_escape_sequence
          sequence = +''
          2.times do
            break unless IO.select([@input], nil, nil, 0.05)

            sequence << @input.getch
          end
          sequence
        end

        # Screen width. 80 if unknown.
        def terminal_width
          width = @output.respond_to?(:winsize) ? @output.winsize[1].to_i : 0
          width = ENV['COLUMNS'].to_i if width < 20
          width < 20 ? 80 : width
        rescue StandardError
          80
        end
      end
    end
  end
end
