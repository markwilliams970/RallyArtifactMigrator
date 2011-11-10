require 'active_support/inflector'
require 'base64'
require 'rally_rest_api'
require 'events'

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
		
		def self.run
			prepare
			
			c = Configuration.singleton.source_config
			c.version = ArtifactMigration::RALLY_API_VERSION if c.version.nil? or c.version.empty?
			
			@@rally_ds = RallyRestAPI.new :username => c.username, :password => c.password, :base_url => c.server, :version => c.version, :http_headers => ArtifactMigration::INTEGRATION_HEADER
						
			emit :begin_export
			[:tag, :release, :iteration, :hierarchical_requirement, :test_folder, :test_case, :test_case_step, :test_set, :test_case_result, :defect, :defect_suite, :task].each do |type|
				if c.migration_types.include? type
					emit :begin_type_export, type
					export_type type 
					emit :end_type_export, type
				end
			end
			
			@@workspace = Helper.find_workspace(@@rally_ds, c.workspace_oid)

			if c.migrate_attachments_flag
				emit :begin_attachment_export
				export_attachments
				emit :end_attachment_export
			end
			
			emit :end_export
		end
		
		def self.prepare
			Schema.drop_all_artifact_tables
			
			Schema.create_artifact_schemas
			Schema.create_object_type_map_schema
			Schema.create_attachment_scheme
			
			attrs = {}
			@@rw_attrs = {}
			
			c = Configuration.singleton.source_config
			ret = Helper.batch_toolkit :url => c.server,
				:username => c.username,
				:password => c.password,
				:version => c.version,
				:workspace => c.workspace_oid,
				:type => :type_definition,
				:fields => %w(Abstract Attributes DisplayName ElementName Name Note Parent)
			
			ret['Results'].each do |r| 
				r['Attributes'].each do |a| 
					attrs[r['ElementName']] = [].to_set unless attrs[r['ElementName']]
					attrs[r['ElementName']] << a['Name'].gsub(' ', '')

					@@rw_attrs[r['ElementName']] = [].to_set unless @@rw_attrs[r['ElementName']]
					@@rw_attrs[r['ElementName']] << a['Name'].gsub(' ', '') unless a['ReadOnly']
				end
			end
			
			if c.version.to_f < 1.27
  			%w(HierarchicalRequirement Defect DefectSuite Task TestCase TestSet).each do |wp|
  				@@rw_attrs[wp] = @@rw_attrs[wp] + %w(Name Notes Owner Tags Package Description FormattedID Project).to_set
  			end
			end
			
			%w(HierarchicalRequirement Defect DefectSuite Task TestCase TestSet).each do |wp|
				@@rw_attrs[wp] = @@rw_attrs[wp] - %w(Successors).to_set
			end
			
			Logger.debug("Columns for TestSet are #{@@rw_attrs['TestSet']}")
			@@rw_attrs.each { |k, v| Schema.update_schema_for_artifact(k.underscore.to_sym, v)}
			
			emit :export_preperation_complete
		end
		
		def self.export_type(type)
			klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
			c = Configuration.singleton.source_config
			
			Logger.info("Exporting #{type} with class [#{klass}]")
			
			c.project_oids.each do |poid|
				Logger.info("Searching Project #{poid}")
				emit :exporting, type, poid
				
				ret = Helper.batch_toolkit :url => c.server,
					:username => c.username,
					:password => c.password,
					:version => c.version,
					:workspace => c.workspace_oid,
					:project => poid,
					:project_scope_up => c.project_scope_up,
					:project_scope_down => c.project_scope_down,
					:type => type,
					:fields => @@rw_attrs[type.to_s.classify] + %w(UserName).to_set
			
				Logger.info("Found #{ret['Results'].size} #{type.to_s.humanize}")
				
				ret["Results"].each do |o|
					attrs = {}
					artifact = nil
					
					o.each do |k, v| 
						if %w(Project PortfolioItem Requirement WorkProduct TestCase Defect DefectSuite TestFolder Parent TestCaseResult Iteration Release TestSet).include? k
							attrs[k.to_s.underscore.to_sym] = v["ObjectID"] if v
						elsif %w(Owner SubmittedBy).include? k
							attrs[k.to_s.underscore.to_sym] = v["UserName"] if v
						elsif %w(Tags Predecessors Successors TestCases Duplicates).include? k
							rels = []
							v.each do |t|
								rels.push t['ObjectID']
							end if v
							
							attrs[k.to_s.underscore.to_sym] = rels.to_json
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
					
					c.ignore_fields[type].each { |a| attrs.delete a } if c.ignore_fields.has_key? type
					
					attrs[:object_i_d] = o["ObjectID"]
					
					artifact = klass.create(attrs) unless klass.find_by_object_i_d(o['ObjectID'].to_i)
					ObjectTypeMap.create(:object_i_d => artifact.object_i_d, :artifact_type => type.to_s) if artifact and ObjectTypeMap.find_by_object_i_d(artifact.object_i_d).nil?
					
					emit :artifact_exported, artifact
					Logger.debug(artifact.attributes) if artifact
				end
			end
		end
	
		def self.export_attachments
			Logger.info("Exporting Attachments")

			c = Configuration.singleton.source_config

			c.project_oids.each do |poid|
				Logger.info("Exporting Attachments for Project OID [#{poid}]")
				
				ret = Helper.batch_toolkit :url => c.server,
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
					
						artifact_res = @@rally_ds.find(:artifact, :project => project, :project_scope_up => false, :project_scope_down => false) { equal :object_i_d, art['ObjectID'] }
						artifact = artifact_res.results.first

						if artifact.attachments

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
											:artifact_i_d => artifact.object_i_d
										}
										
										Attachment.create(attrs) unless Attachment.find_by_object_i_d(attachment.object_i_d)
										ObjectTypeMap.create(:object_i_d => attachment.object_i_d, :artifact_type => 'attachment') if attachment and ObjectTypeMap.find_by_object_i_d(attachment.object_i_d).nil?
										
										emit :attachment_exported, artifact, attachment
									rescue EOFError => e
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