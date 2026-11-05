module IntercomBulkCleaner
  module UI
    class Terminal
      # Colors, messages, boxes, tables.
      module Output
        STYLES = {
          bold: 1,
          dim: 2,
          red: 31,
          green: 32,
          yellow: 33,
          blue: 34,
          magenta: 35,
          cyan: 36,
          gray: 90
        }.freeze
        ANSI = /\e\[[\d;?]*[A-Za-z]/.freeze

        # Add color (real terminals only).
        def paint(text, *styles)
          return text.to_s if !@color || styles.empty?

          "\e[#{styles.map { |style| STYLES.fetch(style) }.join(';')}m#{text}\e[0m"
        end

        def say(text = '')
          @output.puts(text)
        end

        def success(text)
          say "#{paint('✔', :green)} #{text}"
        end

        def warning(text)
          say "#{paint('!', :yellow)} #{text}"
        end

        def error(text)
          say "#{paint('✖', :red)} #{text}"
        end

        def info(text)
          say "#{paint('•', :cyan)} #{text}"
        end

        def muted(text)
          say paint(text, :gray)
        end

        def heading(text)
          say
          say paint(text, :bold, :cyan)
        end

        # Text in a rounded box.
        def box(title, lines, color: :cyan)
          width = ([plain_length(title) + 4] + lines.map { |line| plain_length(line) + 2 }).max
          say paint("╭─ #{title} #{'─' * (width - plain_length(title) - 3)}╮", color)
          lines.each do |line|
            say "#{paint('│', color)} #{line}#{' ' * (width - plain_length(line) - 1)}#{paint('│', color)}"
          end
          say paint("╰#{'─' * width}╯", color)
        end

        # Simple aligned table.
        def table(headers, rows, max_cell: 36)
          cells = ([headers] + rows).map { |row| row.map { |cell| truncate(cell.to_s, max_cell) } }
          widths = headers.each_index.map { |index| cells.map { |row| row[index].to_s.length }.max }
          format_row = ->(row) { row.each_with_index.map { |cell, index| cell.ljust(widths[index]) }.join('  ') }

          say "  #{paint(format_row.call(cells.first), :bold)}"
          say "  #{paint(widths.map { |width| '─' * width }.join('  '), :gray)}"
          cells.drop(1).each { |row| say "  #{format_row.call(row)}" }
        end

        # 1234567 -> 1,234,567
        def number(value)
          value.to_i.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
        end

        private

        # Shorten long text with …
        def truncate(text, max)
          text = text.to_s
          text.length > max ? "#{text[0, [max - 1, 1].max]}…" : text
        end

        # Length without color codes.
        def plain_length(text)
          text.to_s.gsub(ANSI, '').length
        end
      end
    end
  end
end
