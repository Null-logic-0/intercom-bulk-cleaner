module IntercomBulkCleaner
  class App
    # Find contacts and export them.
    module SearchFlows
      ROLES = [['Users', 'user'], ['Leads', 'lead'], ['Users and leads', 'all']].freeze

      FORMATS = [
        ['CSV', 'csv', 'spreadsheet, one row per contact'],
        ['JSON', 'json', 'full contact objects'],
        ['JSONL', 'jsonl', 'one contact per line']
      ].freeze

      def search_flow
        filters = build_filters
        return if filters.nil?

        match = filters.size > 1 ? choose_match : 'all'
        role = choose_role
        query = @query_builder.build_base(filters: filters, match: match, role: role)
        review(queries: [query], kind: 'search', role: role)
      end

      # Email list
      def bulk_flow
        bulk = load_emails
        return if bulk.nil?

        filters = []
        if @ui.yes?('Narrow it down with filters too (dates, tags, plan...)?')
          filters = build_filters
          return if filters.nil?
        end

        match = filters.size > 1 ? choose_match : 'all'
        role = choose_role
        base = @query_builder.build_base(filters: filters, match: match, role: role)
        review(queries: @runner.queries_for(base: base, bulk: bulk), kind: 'bulk', role: role, bulk: bulk)
      end

      def export_all_flow
        role = choose_role
        review(queries: [@query_builder.build_all(role: role)], kind: 'all', role: role)
      end

      private

      # Users, leads or both.
      def choose_role
        @ui.select('Which contacts?', ROLES)
      end

      # Paste emails or pick a file.
      def load_emails
        candidates = (files_in('.', '*.csv') + files_in('.', '*.txt') + files_in(@exports_dir, '*.csv'))
                     .reject { |path| path.end_with?('_not_found.txt') }
        choices = [['Paste emails', :paste, 'type or paste a list']]
        choices += describe_files(candidates).map { |label, path, detail| ["Load #{label}", path, detail] }
        choices << ['Enter a file path...', :manual]

        source = @ui.select('Where are the emails?', choices, filter: choices.size > 8)
        bulk =
          case source
          when :paste then Search::BulkValues.from_text(@ui.multiline('Paste emails (commas, spaces or new lines)'))
          when :manual then Search::BulkValues.from_file(ask_existing_file('File path:'))
          else Search::BulkValues.from_file(source)
          end

        skipped = bulk.skipped.empty? ? '' : @ui.paint(" (#{bulk.skipped.size} invalid skipped)", :yellow)
        @ui.success("Loaded #{@ui.number(bulk.size)} unique emails#{skipped}")
        bulk
      end

      # Count, preview, export, then offer delete.
      def review(queries:, kind:, role:, bulk: nil)
        total = nil

        if bulk
          @ui.info("#{@ui.number(bulk.size)} emails will be searched in #{queries.size} " \
                   "batch#{'es' unless queries.size == 1}.")
        else
          total = @ui.spinner('Counting matching contacts') { @runner.count(queries) }
          if total.zero?
            @ui.warning('No contacts match.')
            return
          end

          @ui.success("#{@ui.paint(@ui.number(total), :bold)} contacts match")
          preview(queries.first, total)
        end

        return unless @ui.select('What next?', [['Export them', :export], ['Back to menu', :back]]) == :export

        format = @ui.select('Format', FORMATS)
        default = File.join(@exports_dir, File.basename(Services::SearchExportRunner.default_output(kind, format)))
        path = @ui.ask('Save to', default: default)
        result = export(queries, path, format, role, bulk, total)
        after_export(result)
      end

      # First rows as a table.
      def preview(query, total)
        contacts = []
        @searcher.each_page(query: query) do |page, _total, _number|
          contacts = page.first(PREVIEW_ROWS)
          break
        end

        @ui.table(%w[Email Name Role Created ID], contacts.map { |contact| contact_row(contact) })
        @ui.muted("  ... and #{@ui.number(total - contacts.size)} more") if total > contacts.size
      end

      # One table row.
      def contact_row(contact)
        created = contact['created_at'] ? Time.at(contact['created_at']).utc.strftime('%Y-%m-%d') : '-'
        [contact['email'] || '-', contact['name'] || '-', contact['role'], created, contact['id']]
      end

      # Export with a progress bar.
      def export(queries, path, format, role, bulk, total)
        bar = @ui.progress('Exporting', total: total)
        on_progress = lambda do |exported, target, batch, batches|
          bar.update(exported, total: target, detail: batches > 1 ? "batch #{batch}/#{batches}" : nil)
        end

        result = @runner.run(queries: queries, output: path, bulk: bulk, role: role, format: format,
                             on_progress: on_progress)
        bar.finish
        report_export(result, role)
        result
      end

      # Show what was saved and what wasn't found.
      def report_export(result, role)
        if result.exported.zero?
          @ui.warning('No contacts matched. Nothing was saved.')
        else
          @ui.success("Saved #{@ui.paint(@ui.number(result.exported),
                                         :bold)} contacts to #{@ui.paint(result.output, :cyan)}")
        end
        return unless result.bulk_total

        @ui.info("Matched #{@ui.number(result.matched)} of #{@ui.number(result.bulk_total)} emails")
        @ui.warning("#{result.skipped.size} invalid emails were skipped") unless result.skipped.empty?
        return if result.missing.empty?

        @ui.warning("#{@ui.number(result.missing.size)} not found, listed in #{result.missing_path}")
        @ui.muted("  Only #{role}s were searched. Choose \"Users and leads\" to include both.") unless role == 'all'
      end

      # Offer to delete what was just exported.
      def after_export(result)
        return if result.exported.zero?

        choice = @ui.select('What next?', [
                              ["Delete these #{@ui.number(result.exported)} contacts", :delete,
                               'preview and confirm first'],
                              ['Back to menu', :menu]
                            ])
        delete_flow(path: result.output) if choice == :delete
      end
    end
  end
end
