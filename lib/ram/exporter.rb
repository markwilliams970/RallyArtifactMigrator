require 'active_support/inflector'
require 'base64'
require 'events'
require 'rally_api'
require 'time'
require 'json'

=begin

Events

:export_preperation_complete
:begin_export
:begin_type_export
:artifact_exported
:end_type_export
:begin_attachment_export
:end_attachment_export
:end_export

=end

module ArtifactMigration
	class Exporter
		extend Events::Emitter
		
		def self.reset_transaction_log
			DatabaseConnection.ensure_database_connection
	    
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				if ImportTransactionLog.table_exists?
					drop_table ImportTransactionLog.table_name.to_sym
				end
			  
				if IssueTransactionLog.table_exists?
					drop_table IssueTransactionLog.table_name.to_sym
				end
			  
				if ObjectIdMap.table_exists?
					drop_table ObjectIdMap.table_name.to_sym
				end
			end
		end
		
		def self.run

            c = Configuration.singleton.source_config
            c.version = ArtifactMigration::RALLY_API_VERSION if c.version.nil? or c.version.empty?

            puts "Commencing export process..."
			@@start_time = Time.now

			DatabaseConnection.ensure_database_connection
			
			@@update_existing = Configuration.singleton.source_config.update_existing

			prepare

			last_good = Options.find_by_key "LastGoodRun"

			if @@update_existing and last_good
				@@last_update = Time.parse last_good.value
			else
				@@last_update = Time.local(2000, "jan", 1)
			end

			c = Configuration.singleton.source_config
			c.version = ArtifactMigration::RALLY_API_VERSION if c.version.nil? or c.version.empty?

			rconfig = {}
			rconfig[:base_url] = c.server
			rconfig[:username] = c.username
			rconfig[:password] = c.password
			rconfig[:version] = c.version
			rconfig[:headers] = ArtifactMigration::INTEGRATION_HEADER
			rconfig[:logger] = ::Logger.new("rallydev.exporter.log")
			rconfig[:debug] = true
			
			@@rally_ds = RallyAPI::RallyRestJson.new rconfig
			@@workspace = { "_ref" => "#{c.server}/webservice/#{c.version}/workspace/#{c.workspace_oid}.js" }

			emit :begin_export

			if c.migrate_projects_flag
                puts "Exporting projects..."
				self.export_projects
			end

			ArtifactMigration::UE_TYPES.each do |type|
				Logger.debug "Checking for type #{type} - #{c.migration_types.include? type}"
				if c.migration_types.include? type
					emit :begin_type_export, type

					if [:release, :iteration, :hierarchicalrequirement, :defect, :defectsuite, :task, :testcase, :portfolioitem].include? type
                        puts "Exporting #{type}s at project-scope..."
						export_project_type type 
                    else
                        puts "Exporting #{type}s at workspace-scope..."
                        export_workspace_type type
					end

					emit :end_type_export, type
				end
			end

			if c.migrate_attachments_flag
				emit :begin_attachment_export
				export_attachments2
				emit :end_attachment_export
			end

			unless Options.find_by_key('LastGoodRun').nil?
				Options.find_by_key('LastGoodRun').update_attributes({:value => @@start_time})
			else
				Options.create({:key => 'LastGoodRun', :value => @@start_time})
			end

			emit :end_export
		end

		def self.prepare

            c = Configuration.singleton.source_config
            c.version = ArtifactMigration::RALLY_API_VERSION if c.version.nil? or c.version.empty?

            rconfig = {}
            rconfig[:base_url] = c.server
            rconfig[:username] = c.username
            rconfig[:password] = c.password
            rconfig[:version] = c.version
            rconfig[:headers] = ArtifactMigration::INTEGRATION_HEADER
            rconfig[:logger] = ::Logger.new("rallydev.exporter.log")
            rconfig[:debug] = true

            @@rally_ds = RallyAPI::RallyRestJson.new rconfig
            @@workspace = { "_ref" => "#{c.server}/webservice/#{c.version}/workspace/#{c.workspace_oid}.js" }

            puts "Preparing schema..."
			Schema.create_options_schema

			unless @@update_existing
				Schema.drop_all_artifact_tables

				Schema.create_artifact_schemas
				Schema.create_attachments_list_schema
				Schema.create_object_type_map_schema
				Schema.create_project_scheme
				Schema.create_attachment_schema
				Schema.create_attribute_value_schema
			end

			attrs = {}
			@@rw_attrs = {}

			c = Configuration.singleton.source_config

            workspace = Helper.find_workspace(@@rally_ds, c.workspace_oid)
            workspace_name = workspace["Name"]

			ret = Helper.rally_api :url => c.server,
				:username => c.username,
				:password => c.password,
				:version => c.version,
				:workspace => workspace_name,
				:type => :typedefinition,
				:fields => %w(Abstract Attributes DisplayName ElementName Name Note Parent)

			ret['Results'].each do |r| 
				r['Attributes'].each do |a| 
					attrs[r['ElementName']] = [].to_set unless attrs[r['ElementName']]
					attrs[r['ElementName']] << a['Name'].gsub(' ', '')

					@@rw_attrs[r['ElementName'].downcase] = [].to_set unless @@rw_attrs[r['ElementName'].downcase]
					@@rw_attrs[r['ElementName'].downcase] << a['Name'].gsub(' ', '') unless a['ReadOnly']
				end
            end

			#if c.version.to_f < 1.27
			%w(HierarchicalRequirement Defect DefectSuite Task TestCase TestSet).each do |wp|
				Logger.debug "Updating Attributes for type #{wp}"
                puts "Updating Attributes for type #{wp}"

				if (@@rw_attrs.has_key? wp.downcase)
					@@rw_attrs[wp.downcase] = @@rw_attrs[wp.downcase] + %w(Name Notes Owner Tags Package Description FormattedID Project Attachments).to_set
				end
			end
			#end

			#@@rw_attrs['Task'] = @@rw_attrs['Task'] + %w(Project).to_set

			%w(HierarchicalRequirement Defect DefectSuite Task TestCase TestSet).each do |wp|
				if @@rw_attrs.has_key? wp.downcase
					@@rw_attrs[wp.downcase] = @@rw_attrs[wp.downcase] - %w(Successors).to_set
				end
			end

			#Logger.debug("Columns for TestSet are #{@@rw_attrs['TestSet']}")

			@@rw_attrs.each { |k, v| Logger.debug "Type #{k} has columns #{v}" }
			@@rw_attrs.each { |k, v| Schema.update_schema_for_artifact(k.downcase.to_sym, v)}

            puts "Schema Preparation complete..."
			emit :export_preperation_complete
		end

		def self.export_project_type(type)
			klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
			c = Configuration.singleton.source_config
			Logger.info("Exporting #{type} with class [#{klass}]")

			c.project_oids.each do |poid|
				export_type(type, c.workspace_oid, poid)
			end
		end

		def self.export_workspace_type(type)
			klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
			c = Configuration.singleton.source_config
			Logger.info("Exporting #{type} with class [#{klass}]")

			export_type(type, c.workspace_oid, nil)
		end

		def self.export_type(type, woid, poid)
            puts "Exporting #{type}s..."
			klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
			c = Configuration.singleton.source_config

            workspace = Helper.find_workspace(@@rally_ds, woid)
            workspace_name = workspace["Name"]

            project_name = nil
			if (poid)
                project           = Helper.find_project(@@rally_ds, workspace, poid)
                project_name      = project["Name"]
				Logger.info("Searching Project #{poid}")
				emit :exporting, type, poid
			else
				Logger.info("Searching Workspace #{woid}")
				emit :exporting, type, woid
			end


			if %w(HierarchicalRequirement Defect DefectSuite Task TestCase PortfolioItem).include? type
				query = "(LastUpdateDate >= #{@@last_update.utc.iso8601.to_s})"
			else
				query = ""
            end

            if (poid)
                ret = Helper.rally_api :url => c.server,
                    :username => c.username,
                    :password => c.password,
                    :version => c.version,
                    :workspace => workspace_name,
                    :project => project_name,
                    :project_scope_up => c.project_scope_up,
                    :project_scope_down => c.project_scope_down,
                    :type => type,
                    :query => query,
                    :fields => @@rw_attrs[type.to_s] + %w(UserName).to_set
            else
                ret = Helper.rally_api :url => c.server,
                   :username => c.username,
                   :password => c.password,
                   :version => c.version,
                   :workspace => workspace_name,
                   :project_scope_up => c.project_scope_up,
                   :project_scope_down => c.project_scope_down,
                   :type => type,
                   :query => query,
                   :fields => @@rw_attrs[type.to_s] + %w(UserName).to_set
            end

			Logger.info("Found #{ret['Results'].total_result_count} #{type.to_s.humanize}")
            puts "Found #{ret['Results'].total_result_count} #{type.to_s.humanize}"

			ret["Results"].each do |o|
				attrs = {}
				artifact = nil

                k = o._type
                # Elements is the attr accessor on rally_api's RallyObject that gets you an iterable
                # hash of key,value pairs
                elements = o.elements
                elements.each do |k, v|
                    if %w(Project PortfolioItem Requirement WorkProduct TestCase Defect DefectSuite TestFolder Parent TestCaseResult Iteration Release TestSet).include? k
                        attrs[k.to_s.underscore.to_sym] = v["ObjectID"] if v
                    elsif %w(PreliminaryEstimate PortfolioItemType).include? k # TODO: Make generic
                        if (type == :portfolioitem)
                            Logger.debug "Transforming #{k} - #{v['Name']}" unless v.nil?
                            attrs[k.to_s.underscore.to_sym] = v['Name'] unless v.nil?
                            Logger.debug "#{k.to_s.underscore.to_sym} => #{attrs[k.to_s.underscore.to_sym]}"
                        end
                    elsif %w(Owner SubmittedBy).include? k
                        attrs[k.to_s.underscore.to_sym] = v["UserName"] if v
                    elsif %w(Tags Predecessors Successors TestCases Duplicates).include? k
                        rels = []
                        v.each do |t|
                            rels.push t['ObjectID']
                        end if v

                        attrs[k.to_s.underscore.to_sym] = rels.to_json
                    elsif %w(Attachments).include? k
                        Logger.debug "Found Attachments - #{v}" if v.size > 0
                        v.each do |attach|
                            if AttachmentsList.find_by_object_i_d(attach["ObjectID"]).nil?
                                AttachmentsList.create(:object_i_d => attach["ObjectID"], :artifact_i_d => o["ObjectID"])
                                Logger.debug "Adding Attachment - #{attach}"
                            end
                        end
                    else
                        if v.class == Hash
                            if v.has_key? "LinkID"
                                attrs[k.to_s.underscore.to_sym] = v.to_json if klass.column_names.include? k.to_s.underscore
                            end
                        else
                            attrs[k.to_s.underscore.to_sym] = v.to_s if klass.column_names.include? k.to_s.underscore
                        end
                    end
                end

				# o.each do |k, v|
				# 	if %w(Project PortfolioItem Requirement WorkProduct TestCase Defect DefectSuite TestFolder Parent TestCaseResult Iteration Release TestSet).include? k
				# 		attrs[k.to_s.underscore.to_sym] = v["ObjectID"] if v
				# 	elsif %w(PreliminaryEstimate PortfolioItemType).include? k # TODO: Make generic
				# 		if (type == :portfolioitem)
				# 			Logger.debug "Transforming #{k} - #{v['Name']}" unless v.nil?
				# 			attrs[k.to_s.underscore.to_sym] = v['Name'] unless v.nil?
				# 			Logger.debug "#{k.to_s.underscore.to_sym} => #{attrs[k.to_s.underscore.to_sym]}"
				# 		end
				# 	elsif %w(Owner SubmittedBy).include? k
				# 		attrs[k.to_s.underscore.to_sym] = v["UserName"] if v
				# 	elsif %w(Tags Predecessors Successors TestCases Duplicates).include? k
				# 		rels = []
				# 		v.each do |t|
				# 			rels.push t['ObjectID']
				# 		end if v
                #
				# 		attrs[k.to_s.underscore.to_sym] = rels.to_json
				# 	elsif %w(Attachments).include? k
				# 		Logger.debug "Found Attachments - #{v}" if v.size > 0
				# 		v.each do |attach|
				# 			if AttachmentsList.find_by_object_i_d(attach["ObjectID"]).nil?
				# 				AttachmentsList.create(:object_i_d => attach["ObjectID"], :artifact_i_d => o["ObjectID"])
				# 				Logger.debug "Adding Attachment - #{attach}"
				# 			end
				# 		end
				# 	else
				# 		if v.class == Hash
				# 			if v.has_key? "LinkID"
				# 				attrs[k.to_s.underscore.to_sym] = v.to_json if klass.column_names.include? k.to_s.underscore
				# 			end
				# 		else
				# 			attrs[k.to_s.underscore.to_sym] = v.to_s if klass.column_names.include? k.to_s.underscore
				# 		end
				# 	end
				# end

				c.ignore_fields[type].each { |a| attrs.delete a } if c.ignore_fields.has_key? type

				attrs[:object_i_d] = o["ObjectID"]
				#Logger.debug(attrs)
				unless klass.find_by_object_i_d(o['ObjectID'].to_i).nil?
					artifact = klass.find_by_object_i_d(o['ObjectID'].to_i)
					artifact.update_attributes(attrs)
				else
					artifact = klass.create(attrs)
					ObjectTypeMap.create(:object_i_d => artifact['ObjectID'], :artifact_type => type.to_s) if artifact and ObjectTypeMap.find_by_object_i_d(artifact.object_i_d).nil?
				end

				emit :artifact_exported, artifact
				Logger.debug(artifact.attributes) if artifact
			end
		end

		def self.collect_child_projects(project_list, parent_id)
			ret = []

			project_list.each do |p|
				if p.has_key? 'Parent'
					if p["Parent"]
						if p["Parent"]["ObjectID"].to_i == parent_id.to_i
							ret << p["ObjectID"]
							ret.concat collect_child_projects(project_list, p["ObjectID"])
						end
					end
				end
			end

			ret
		end

		def self.export_projects
			Logger.info("Exporting Projects")

			c = Configuration.singleton.source_config

            workspace = Helper.find_workspace(@@rally_ds, c.workspace_oid)
            workspace_name = workspace["Name"]

			ret = Helper.rally_api :url => c.server,
				:username => c.username,
				:password => c.password,
				:version => c.version,
				:workspace => workspace_name,
				:project_scope_up => c.project_scope_up,
				:project_scope_down => c.project_scope_down,
				:type => :project,
				:fields => %w(ObjectID Name Owner Description Parent State UserName).to_set

            results = ret['Results']

            projects = {}
            results.each do | this_project |
                this_poid = this_project["ObjectID"].to_s
                projects[this_poid] = this_project
            end

			#projects = Hash[ ret['Results'].collect { |elt| [elt['ObjectID'], elt] } ]
            #puts projects

			all_projects = [].concat c.project_oids.to_a
			c.project_oids.each { |poid| all_projects << collect_child_projects(ret['Results'], poid.to_i) } if c.migrate_child_projects_flag

			Logger.debug "All Projects: #{all_projects}"
			all_projects.flatten.uniq.each { |poid| c.add_project_oid poid }
			
			c.project_oids.each do |poid|
				Logger.info("Exporting Project Info for Project OID [#{poid}]")
                puts "Exporting Project Info for Project OID #{poid}"
				p = projects[poid.to_s]

				pp = nil
				ppoid = -1

				pp = p["Parent"] if p.has_key? "Parent"
				ppoid = pp["ObjectID"] if pp

				ArtifactMigration::Project.find_or_create_by_source_object_i_d(:source_object_i_d => p['ObjectID'], :source_parent_i_d => ppoid, :name => p["Name"], :description => p["Description"], :owner => p["Owner"]["UserName"], :state => p["State"])
			end

			if c.migrate_project_permissions_flag
				ret = Helper.rally_api :url => c.server,
					:username => c.username,
					:password => c.password,
					:version => c.version,
					:workspace => workspace_name,
					:project_scope_up => c.project_scope_up,
					:project_scope_down => c.project_scope_down,
					:type => :workspacepermission,
					:fields => %w(ObjectID User Role Workspace UserName Name).to_set

				ret["Results"].each { |wp| ArtifactMigration::WorkspacePermission.create(:workspace_i_d => wp["Workspace"]["ObjectID"], :user => wp["User"]["UserName"], :role => wp["Role"]) }

				ret = Helper.rally_api :url => c.server,
					:username => c.username,
					:password => c.password,
					:version => c.version,
					:workspace => workspace_name,
					:project_scope_up => c.project_scope_up,
					:project_scope_down => c.project_scope_down,
					:type => :projectpermission,
					:fields => %w(ObjectID User Role Project UserName Name).to_set

				ret["Results"].each do |pp|
					if projects.has_key? pp["Project"]["ObjectID"]
						ArtifactMigration::ProjectPermission.create(:project_i_d => pp["Project"]["ObjectID"], :user => pp["User"]["UserName"], :role => pp["Role"])
					end
				end
			end
		end

		def self.export_attachments2
			Logger.info("Exporting Attachments")

			emit :saving_attachments_begin, AttachmentsList.count

      AttachmentsList.all.each do |attl|
        attachment = @@rally_ds.read(:attachment, attl.object_i_d)

				Logger.info "\tAttachment: #{attachment["Name"]}"

        art_oid = attl.artifact_i_d.to_s

        Dir::mkdir('Attachments') unless File.exists?('Attachments')
        Dir::mkdir(File.join('Attachments', art_oid)) unless File.exist?(File.join('Attachments', art_oid))

        File.open(File.join('Attachments', art_oid, attachment["ObjectID"].to_s), "w") do |f|
          begin
            Logger.debug "Attachment details - #{attachment}"

            content = attachment["Content"].read({:fetch => "Content"})
            Logger.debug "Attachment Content - #{content}"

            f.write(Base64.decode64(content["Content"]))

            attrs = {
              :object_i_d => attachment["ObjectID"],
              :name => attachment["Name"],
              :description => attachment["Description"], 
              :user_name => attachment["User"]["UserName"],
              :artifact_i_d => art_oid.to_i,
              :content_type => attachment["ContentType"]
            }

            Attachment.create(attrs) unless Attachment.find_by_object_i_d(attachment["ObjectID"])
            ObjectTypeMap.create(:object_i_d => attachment["ObjectID"], :artifact_type => 'attachment') if attachment and ObjectTypeMap.find_by_object_i_d(attachment["ObjectID"]).nil?

            emit :attachment_exported, attl.artifact_i_d, attachment
          rescue EOFError
            f.rewind
            Logger.debug "Error saving file, retrying..."

            emit :attachment_export_failed, att_oid, attachment

            retry
          end
				end
				emit :saving_attachments_end, AttachmentsList.count
			end
		end

		def self.export_attachments
			Logger.info("Exporting Attachments")

			c = Configuration.singleton.source_config

			c.project_oids.each do |poid|
				Logger.info("Exporting Attachments for Project OID [#{poid}]")

				ret = Helper.rally_api :url => c.server,
					:username => c.username,
					:password => c.password,
					:version => c.version,
					:workspace => c.workspace_oid,
					:project => poid,
					:project_scope_up => c.project_scope_up,
					:project_scope_down => c.project_scope_down,
					:type => :artifact,
					:fields => %w(ObjectID Attachments Name).to_set

				project = Helper.find_project(@@rally_ds, @@workspace, poid) if ret["Results"].size > 0

				emit :saving_attachments_begin, ret["Results"].size
				ret["Results"].each do |art|
					if (art['Attachments'] and (art['Attachments'].size > 0))
						Logger.info "#{art['Name']} [#{art['ObjectID']}] has #{art['Attachments'].size} Attachments"

						artifact_res = @@rally_ds.find(
                            :artifact, :fetch => true,
                            :project => project,
                            :project_scope_up => false,
                            :project_scope_down => false) { equal :object_i_d, art['ObjectID'] }
						Logger.debug "Found Artifact: #{artifact_res.results}"

                        artifact = artifact_res.results.first

						if artifact and artifact.attachments

							artifact.attachments.each do |attachment|
								Logger.info "\tAttachment: #{attachment.name}"

								Dir::mkdir('Attachments') unless File.exists?('Attachments')
								Dir::mkdir(File.join('Attachments', artifact.object_i_d)) unless File.exist?(File.join('Attachments', artifact.object_i_d))

								File.open(File.join('Attachments', artifact.object_i_d, attachment.object_i_d), "w") do |f|
									begin
										f.write(Base64.decode64(attachment.content.content))

										attrs = {
											:object_i_d => attachment.object_i_d,
											:name => attachment.name,
											:description => attachment.description, 
											:user_name => attachment.user.user_name,
											:artifact_i_d => artifact.object_i_d,
											:content_type => attachment.content_type
										}

										Attachment.create(attrs) unless Attachment.find_by_object_i_d(attachment.object_i_d)
										ObjectTypeMap.create(:object_i_d => attachment.object_i_d, :artifact_type => 'attachment') if attachment and ObjectTypeMap.find_by_object_i_d(attachment.object_i_d).nil?

										emit :attachment_exported, artifact, attachment
									rescue EOFError
										f.rewind
										Logger.debug "Error saving file, retrying..."

										emit :attachment_export_failed, artifact, attachment

										retry
									end
								end unless File.exists? File.join('Attachments', artifact.object_i_d, attachment.object_i_d)
							end
						end
					end
				end
				emit :saving_attachments_end, ret["Results"].size
			end
		end
	end
end