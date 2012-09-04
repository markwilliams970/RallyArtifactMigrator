#require 'progress_bar'
require 'highline'
require 'rainbow'

module ArtifactMigration
	class CLI
		
		def setup_export
			progress = nil
			current_project = nil
			label = nil
			
			Exporter.on(:exporting) { |type, pid| current_project = pid }
			
			Exporter.on(:saving_attachments_begin) do |count|
				if count > 0
					progress = ProgressBar.new count, "Exporting Attachments", :bar, :counter, :rate, :eta
				else
					puts "No attachments to export"
				end
			end
			Exporter.on(:attachment_exported) { |art, att| progress.increment! if progress }
			#Exporter.on(:attachment_failed) { |art, att| progress.increment! if progress }
			Exporter.on(:saving_attachments_end) { progress = nil }
			
			Helper.on(:batch_toolkit_begin) do |type|
				if current_project
					label = "Exporting #{type.to_s.titleize} for Project #{current_project}"
				else
					label = "Exporting #{type.to_s.titleize}"
				end
				
				progress = ProgressBar.new 200, label, :label, :bar, :counter, :rate, :eta
			end
			
			Helper.on(:batch_toolkit_end) do |type|
				puts '' if progress.max > 0
				progress = nil
			end
			
			Helper.on(:batch_toolkit_processed) do |count, total|
				count = total if count > total
				progress.max = total
				progress.count = count

				if total > 0
					progress.write
				else
					puts "[#{label}] None found"
				end
			end
		end
		
		def setup_import
			progress = nil
			label = nil
			
			Importer.on(:begin_type_import) do |type| 
				progress = ProgressBar.new 200, "Importing #{type.to_s.titleize}", :label, :bar, :counter, :rate, :eta
			end

			[:end_type_import, :end_import_projects, :end_update_artifact_rank, :end_update_project_parents, :end_import_project_permissions, :end_update_story_parents, :end_update_portfolio_item_parents, :end_update_story_predecessors, :end_update_artifact_statuses, :end_test_folder_reparent, :end_update_defect_duplicates, :end_attachment_import].each do |event|
				Importer.on(event) do |type| 
			    if progress
					  puts "" if progress.count > 0
					end
					progress = nil
				end
			end
			
			Importer.on(:update_status_begin) do |type, count|
				label = "Updating Statuses of #{type.to_s.titleize}"
				if count > 0
					progress = ProgressBar.new count, label, :label, :bar, :counter, :rate, :eta
				else
					puts "[#{label}] None to update"
				end
					
			end
						
			[:import_type_count, :begin_import_projects, :begin_update_artifact_rank, :begin_update_project_parents, :begin_import_project_permissions, :begin_update_story_parents, :begin_update_portfolio_item_parents, :begin_update_story_predecessors, :begin_test_folder_reparent, :begin_update_defect_duplicates, :begin_attachment_import].each do |event|
				Importer.on(event) do |count|
					label = case event
						when :begin_update_story_parents
							"Updating Story Parents"
						when :begin_update_portfolio_item_parents
							"Updating Portfolio Parents"
						when :begin_update_story_predecessors
							"Updating Story Predecessors"
						when :begin_update_artifact_rank
							"Fixing Artifact Ranks"
						when :begin_update_artifact_statuses
							"Fixing Artifact Statuses"
						when :begin_test_folder_reparent
							"Updating Test Folder Parents"
						when :begin_update_defect_duplicates
							"Updating Defect Duplicates"
						when :begin_attachment_import
							"Importing Attachments"
						when :begin_import_projects
						  "Importing Projects"
						when :begin_update_project_parents
						  "Updating Project Parents"
						when :begin_import_project_permissions
						  "Importing Project Permissions"
						else
							if progress
								progress.label
							else
								nil
							end
					end
					
					progress = ProgressBar.new 200, label, :label, :bar, :counter, :rate, :eta	unless progress
					
					if (count > 0)
						progress.max = count
					else
						puts "[#{label}] None to be updated"
					end
				end
			end
			
			Importer.on(:loop) do
					progress.increment! if progress
			end
		end
		
		def self.run_export
			export_cli = CLI.new
			export_cli.setup_export
			
			ArtifactMigration::Exporter.run
			
			export_cli = nil
		end
		
		def self.run_import
			import_cli = CLI.new
			import_cli.setup_import
			
			ArtifactMigration::Importer.run
			
			import_cli = nil
		end
		
		def self.run_verification
			hl = HighLine.new
			
			Validator.on(:verify_source) { puts "---Verifying Source Configuration" }
			Validator.on(:verify_target) { puts "---Verifying Target Configuration" }
			
			Validator.on(:validation) do |message, success|
				width = hl.output_cols.to_i
				width = width - message.length
				width = width - (success ? 5 : 4)
				
				puts message + ".".rjust(width, '.') + "[" +  (success ? "YES".color(:green) : "NO".color(:red)) + "]"
			end
			
			ArtifactMigration::Validator.verify
		end
	end
end
