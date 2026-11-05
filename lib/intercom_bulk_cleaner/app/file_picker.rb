module IntercomBulkCleaner
	class App
		# Pick files: exports, deletion logs, email lists.
		module FilePicker
			private

			# Export files: csv, json, jsonl.
			def export_files
				%w[csv json jsonl].flat_map { |ext| files_in(@exports_dir, "*.#{ext}") }
			end

			def files_in(dir, pattern)
				Dir.glob(File.join(dir, pattern)).select { |path| File.file?(path) }
			end

			# Pick from the list, or type a path.
			def choose_file(question, paths, kind:)
				if paths.empty?
					@ui.muted("No #{kind} files found yet.")
					return ask_existing_file("File path:")
				end

				choices = describe_files(paths)
				choices << ["Enter a file path...", :manual]

				choice = @ui.select(question, choices, filter: choices.size > 8)
				choice == :manual ? ask_existing_file("File path:") : choice
			end

			# Label, path and "rows · age", newest first.
			def describe_files(paths)
				paths.uniq.sort_by { |path| -File.mtime(path).to_f }.map do |path|
					[path.delete_prefix("./"), path, "#{count_entries(path)} · #{age(File.mtime(path))}"]
				end
			end

			# Rows, lines or size.
			def count_entries(path)
				case File.extname(path)
				when ".json" then "#{(File.size(path) / 1024.0).ceil} KB"
				when ".txt" then "#{@ui.number(File.foreach(path).count { |line| !line.strip.empty? })} lines"
				else
					rows = File.foreach(path).count { |line| !line.strip.empty? }
					rows -= 1 if File.extname(path) == ".csv"
					"#{@ui.number(rows)} rows"
				end
			end

			# "5 min ago"
			def age(time)
				seconds = Time.now - time
				return "just now" if seconds < 60
				return "#{(seconds / 60).floor} min ago" if seconds < 3600
				return "#{(seconds / 3600).floor} h ago" if seconds < 86_400

				"#{(seconds / 86_400).floor} days ago"
			end

			# Ask for a path that exists.
			def ask_existing_file(question)
				path = @ui.ask(question, validate: ->(answer) { File.file?(File.expand_path(answer)) ? nil : "File not found: #{answer}" })
				File.expand_path(path)
			end
		end
	end
end
