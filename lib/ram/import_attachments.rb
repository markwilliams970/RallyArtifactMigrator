require 'active_support/inflector'
require 'rally_rest_api'
require 'json'
require 'net/http'
require 'net/https'
require 'events'

module ArtifactMigration
	class ImportAttachments
		extend Events::Emitter
		
		def self.prepare
			config = Configuration.singleton.target_config
			config.version = ArtifactMigration::RALLY_API_VERSION if config.version.nil?
			
			@@rally_ds = RallyRestAPI.new :username => config.username, :password => config.password, :base_url => config.server, :version => config.version, :http_headers => ArtifactMigration::INTEGRATION_HEADER
			@@workspace = Helper.find_workspace @@rally_ds, config.workspace_oid
		  @@object_manager = ObjectManager.new @@rally_ds, @@workspace
		end
		
		def self.import_attachments
			Logger.info "Importing Attachments"
			
			Logger.debug "Switching Workspaces to OID #{@@workspace}"
			prefs = @@rally_ds.user.user_profile
			
			old_ws = prefs.default_workspace
			old_p = prefs.default_project
		
			Logger.debug "Old Default Workspace #{old_ws}/#{old_p}"
			prefs.update(:default_workspace => @@workspace)
			Logger.debug "New Default Workspace #{prefs.default_workspace}/#{prefs.default_project}"
			
			config = Configuration.singleton.target_config
			token = get_rally_security_token
			attachment_new_url = "ax/newAttachment.sp"
			attachment_create_url = "ax/create.sp"

			client = RestClient::Resource.new("#{config.server}", :verify_ssl => false, :headers => {'Cookie' => token})
			
			res = client['switchWorkspace.sp'].post("wOid=#{config.workspace_oid}")
			#Logger.debug res
			
			emit :begin_attachment_import, ArtifactMigration::Attachment.count
			ArtifactMigration::Attachment.all.each do |attachment|
				source_aid = attachment.artifact_i_d
				target_aid = @@object_manager.get_mapped_artifact source_aid
				att_id = attachment.object_i_d
				
				next if ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", att_id, 'import').exists?
				
				file_name = File.join('Attachments', "#{source_aid}", "#{att_id}")
				Logger.debug "Begin upload for #{file_name} || #{target_aid.object_i_d}"
				
				#client["#{attachment_new_url}?oid=#{target_aid.object_i_d}"].get
				res = client[attachment_create_url].post(:fileName => attachment.name, :file => File.new(File.join('Attachments', "#{source_aid}", "#{att_id}"), 'rb'), :oid => target_aid.object_i_d, :enclosure => attachment.description)
				
				Logger.debug res.body
				Logger.debug(res.body.include? %q(<body onload="if(window.opener){window.opener.setTimeout('refreshWindow()', 0);}window.close();"></body>))
				
				success = res.body.include? %q(<body onload="if(window.opener){window.opener.setTimeout('refreshWindow()', 0);}window.close();"></body>)
				
				if success
					Logger.info "Uploaded Attachment #{attachment.name} for Artifact #{target_aid}"
					ImportTransactionLog.create(:object_i_d => att_id, :transaction_type => 'import')
				else
					Logger.info "FAILED to upload Attachment #{attachment.name} for Artifact #{target_aid}"
				end
				
				emit :loop
			end
			emit :end_attachment_import
			
			prefs.update(:default_workspace => old_ws, :default_project => old_p)
		end
		
		def self.switch_user_default_workspace(user, workspace)
			prefs = user.user_profile
			
			old_ws = prefs.default_workspace
			old_p = prefs.default_project
		
			Logger.debug "Old Default Workspace #{old_ws}/#{old_p}"
			prefs.update(:default_workspace => workspace)
			Logger.debug "New Default Workspace #{prefs.default_workspace}/#{prefs.default_project}"
			
			return [old_ws, old_p]
	  end

		def self.switch_user_default_workspace_and_project(user, workspace, project)
			prefs = user.user_profile
			
			old_ws = prefs.default_workspace
			old_p = prefs.default_project
		
			Logger.debug "Old Default Workspace #{old_ws}/#{old_p}"
			prefs.update(:default_workspace => workspace, :defalut_project => project)
			Logger.debug "New Default Workspace #{prefs.default_workspace}/#{prefs.default_project}"
			
			return [old_ws, old_p]
	  end

    def self.import_attachments_new(description, opts = {})
			Logger.info "Importing Attachments with Stateless Editor"
			old_ws, old_p = switch_user_default_workspace @@rally_ds.user, @@workspace
			Logger.debug "Switching Workspaces to OID #{@@workspace}"
    	
    	config = Configuration.singleton.target_config
			
    	workspace_oid = config.workspace_oid
    	token = get_rally_security_token

    	adhoc = RestClient::Resource.new("#{config.server}", :verify_ssl => false, :headers => { 'Cookie' => token } )
    	res = adhoc['switchWorkspace.sp'].post("wOid=#{workspace_oid}")

      def get_prefix(source_oid)
        target_type = ArtifactMigration::ObjectTypeMap.find_by_object_i_d source_oid
        case target_type
          when 'defect' then 'df'
          when 'hierarchical_requirement' then 'ar'
          when 'task' then 'tk'
          when 'test_case' then 'tc'
        end
      end

			emit :begin_attachment_import, ArtifactMigration::Attachment.count
			ArtifactMigration::Attachment.all.each do |attachment|
				source_aid = attachment.artifact_i_d
				target_aid = @@object_manager.get_mapped_artifact source_aid
				target_oid = target_aid.object_i_d
				att_id = attachment.object_i_d
				project_oid = target_aid.project.object_i_d
				
				next if ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", att_id, 'import').exists?
				
				file_name = File.join('Attachments', "#{source_aid}", "#{att_id}")
				Logger.debug "Begin upload for #{file_name} || #{target_aid.object_i_d}"
				
				#client["#{attachment_new_url}?oid=#{target_aid.object_i_d}"].get
				#res = client[attachment_create_url].post(:fileName => attachment.name, :file => File.new(File.join('Attachments', "#{source_aid}", "#{att_id}"), 'rb'), :oid => target_aid.object_i_d, :enclosure => attachment.description)
    	  urlp = "cpoid=#{project_oid}&projectScopeUp=false&projectScopeDown=true"
    	  postp = {}
    	  version = 0
    		res = adhoc["#{get_prefix(source_aid)}/edit.sp?#{urlp}&oid=#{target_oid}"].get
    		doc = Nokogiri::HTML(res)
      	doc.xpath('//input').each do |input|
      	  #puts "#{input['name']} = #{input['value']}"
    	    postp[input['name'].to_s.to_sym] = input['value'] if input['type'] == 'hidden'
    	    postp[input['name'].to_s.to_sym] = input['value'] if input['name'].include? 'enclosure'
    	    postp[input['name'].to_s.to_sym] = input['value'] if input['name'].include? 'steps'
      	end

    		#puts res.inspect
    		#puts res.body
    		postp[:fileName] = file_name
    		postp[:file] = File.new file_name
    		postp[:oid] = target_oid
        postp[:creationContext] = "#{urlp}&oid=#{target_oid}"

    		res = adhoc[base_url].post(postp)

    		puts res.body
    		doc = Nokogiri::HTML(res)
      	doc.xpath('//input').each do |input|
      	  puts "#{input['name']} = #{input['value']}"
    	    postp[input['name'].to_s.to_sym] = input['value']
    	    postp[input['name'].to_s.to_sym] = description if input['name'].include? 'enclosure'
      	end

        postp[:editorMode] = 'edit'
        postp[:editorType] = target_type

    		#'-------------------Save Artifact---------------------'
    		postp.delete :file
    		postp.each {|k, v| puts "#{k} = #{v}"}

    		res = adhoc["#{prefix}/edit/update.sp?#{urlp}"].post(postp)
    		doc = Nokogiri::HTML(res)
    		doc.xpath('//input[@name = "version"]').each do |v|
    		  if (v['value'] == postp[:version])
    		    #puts "Version didn't change"
    		    success = false
    		  else
    		    #puts "Version changed"
    		    success = true
    	    end

    	    #puts "Version #{postp[:version]} => #{v['value']}"
    	  end

    		#File.open("save_out.html", 'w') {|f| f.write(res.body) }
				
				if success
					Logger.info "Uploaded Attachment #{attachment.name} for Artifact #{target_aid}"
					ImportTransactionLog.create(:object_i_d => att_id, :transaction_type => 'import')
				else
					Logger.info "FAILED to upload Attachment #{attachment.name} for Artifact #{target_aid}"
				end
				
				emit :loop
			end
			emit :end_attachment_import
			
			prefs.update(:default_workspace => old_ws, :default_project => old_p)
    end

		def self.import_attachments_ws
			Logger.info "Importing Attachments"
			
			config = Configuration.singleton.target_config

			emit :begin_attachment_import, ArtifactMigration::Attachment.count
			ArtifactMigration::Attachment.all.each do |attachment|
				source_aid = attachment.artifact_i_d
				target_aid = @@object_manager.get_mapped_artifact source_aid
				att_id = attachment.object_i_d
				
				next if ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", att_id, 'import').exists?
				
				file_name = File.join('Attachments', "#{source_aid}", "#{att_id}")
				Logger.debug "Begin upload for #{file_name} || #{target_aid.object_i_d}"
				
  		  byte_content = File.read(file_name)
        content_string = Base64.encode64(byte_content)
        
        content = @@rally_ds.create(:attachment_content, :content => content_string)
        @@rally_ds.create( :attachment, 
                      :name => attachment.name,
                      :description => attachment.description,
                      :content => content,
                      :artifact => target_aid,
                      :content_type => attachment.content_type,
                      :size => byte_content.length)
				
				ImportTransactionLog.create(:object_i_d => att_id, :transaction_type => 'import')
        
				emit :loop
			end
			emit :end_attachment_import
	  end
		
		private
		def self.get_rally_security_token
			config = Configuration.singleton.target_config
			security_url = "platform/j_platform_security_check.op"
			
			uri = URI.parse(config.server)
			http = Net::HTTP.new(uri.host, 443)
			http.use_ssl = true

			data = "j_username=#{config.username}&j_password=#{config.password}"
			headers = {}

			Logger.debug "Phase 1 Security Authorization - #{uri.path}/#{security_url}"
			res = http.post2 "#{uri.path}/#{security_url}", data, headers
			Logger.debug "Status Code: #{res.code}"

			cookie = res['set-cookie']

			uri = URI.parse(res['location'])
			#puts uri.path
			headers['Cookie'] = cookie

			Logger.debug "Phase 2 Security Authorization - #{uri.path}"
			res = http.post2 uri.path, 'jsonp=&jsonOnly=', headers
			Logger.debug "Status Code: #{res.code}"

			Logger.debug "Token -- #{cookie}"
			cookie
		end
		
  end
end