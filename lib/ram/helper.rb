require 'rest_client'
require 'base64'
require 'json'
require 'events'

module ArtifactMigration
	class Helper
		extend Events::Emitter
		
		def self.find_workspace_old(rally, workspace_oid)
			Logger.debug "FWS U - #{rally.user.inspect}"
			u = rally.user
			Logger.debug "FWS S - #{u.subscription.inspect}"
			s = u.subscription
			Logger.debug "FWS WSS - #{s.workspaces.inspect}"
			wss = s.workspaces
			wss.each do |ws|
			#rally.find_all(:workspace, :workspace => nil, :fetch => true).each do |ws|
				Logger.debug "Inspecting WS - #{ws}"
				return ws if ws.object_i_d.to_s == workspace_oid.to_s
			end
			
			nil
        end

        # Added for performance
        def self.find_workspace(rally, workspace_oid)

            subscription_query           = RallyAPI::RallyQuery.new()
            subscription_query.type      = :subscription
            subscription_query.fetch     = "Name,SubscriptionID,Workspaces,Name,State,ObjectID"

            results = rally.find(subscription_query)

            # Look for matching workspaces
            results.each do | this_subscription |
                workspaces = this_subscription.Workspaces
                workspaces.each do |this_workspace|
                    Logger.debug "Inspecting WS - #{this_workspace}"

                    this_workspace_oid_string = this_workspace["ObjectID"].to_s
                    return this_workspace if this_workspace_oid_string == workspace_oid.to_s
                end
            end
        end
		
		def self.find_project(rally, workspace, project_oid)

            project_query                          = RallyAPI::RallyQuery.new()
            project_query.workspace                = workspace
            project_query.project                  = nil
            project_query.project_scope_up         = true
            project_query.project_scope_down       = true
            project_query.type                     = :project
            project_query.fetch                    = "Name,State,ObjectID,Workspace,ObjectID"
            project_query.query_string             = "(ObjectID = #{project_oid.to_s})"

            results = rally.find(project_query)

            # Look for matching workspaces
            results.each do | p |
                this_project_oid_string = p["ObjectID"].to_s
                return p if this_project_oid_string == project_oid.to_s
            end
			
			nil
		end

		def self.create_ref(type, oid)
			{"_ref" => "#{type}/#{oid}.js", "ObjectID" => oid}
		end
		
		def self.batch_toolkit(opts = {})
			enc_password = Base64.encode64("#{opts[:username]}:#{opts[:password]}").strip
			base_url = "#{opts[:url]}/webservice/#{opts[:version]}"
			start = 1
			size = 1
			size = opts[:limit] if opts.has_key? :limit
			size = size + 1
			psu = opts[:projectScopeUp] || false
			psd = opts[:projectScopeDown] || false
			ret = {'Results' => []}
			
			adhoc = RestClient::Resource.new("#{base_url}/adhoc.js", 
				:verify_ssl => false, 
				:headers => { 
					:authorization => "Basic #{enc_password}",
					:accept => '*/*; application/javascript',
					:rallyIntegration_name => 'Rally Artifact Migrator',
					:rallyIntegration_version => ArtifactMigration::VERSION,
					:rallyIntegration_vendor => 'Rally Software'
				})
			
			query = "/#{opts[:type].to_s.sub('_', '')}?query=#{opts[:query] or '(ObjectID > 0)'}&fetch=ObjectID,"
			opts[:fields].each do |e|
				query += "#{e},"
			end
			query.chomp! ','
			
			query += '&pagesize=200'
			query += "&projectScopeUp=#{psu}"
			query += "&projectScopeDown=#{psd}"
			query += "&workspace=#{base_url}/workspace/#{opts[:workspace]}" if opts[:workspace]
			query += "&project=#{base_url}/project/#{opts[:project]}" if opts[:project]

			Logger.debug(query)

			emit :batch_toolkit_begin, opts[:type]
			while start < size
				res = adhoc.post( :adHocQuery => ({:adhoc => (query + "&start=#{start}")}.to_json) )
				resj = JSON.parse(res.to_str)

				resj['adhoc'].each do |e|
					if e[0] == 'Results'
						ret['Results'].concat e[1]
					else
						unless opts.has_key? :limit
							size = e[1] if e[0] == 'TotalResultCount'
						end
						ret[e[0]] = e[1]
					end
				end

				start += 200
				emit :batch_toolkit_processed, start, size
			end
			emit :batch_toolkit_end, opts[:type]

			ret
        end

        def self.rally_api(opts = {})

            headers                 = RallyAPI::CustomHttpHeader.new()
            headers.name            = "Rally Artifact Migrator"
            headers.vendor          = "Rally Software"
            headers.version         = ArtifactMigration::VERSION

            config                  = {:base_url => opts[:url]}
            config[:username]       = opts[:username]
            config[:password]       = opts[:password]
            config[:headers]        = headers #from RallyAPI::CustomHttpHeader.new()
            config[:version]        = opts[:version]
            config[:workspace]      = opts[:workspace] if opts[:workspace]
            config[:project]        = opts[:project] if opts[:project]

            rally_api = RallyAPI::RallyRestJson.new(config)

            # Parameterize fetch
            fetch = ""
            opts[:fields].each do |e|
                fetch += "#{e},"
            end
            fetch.chomp! ','

            # Setup query parameters
            query_string                 = opts[:query] || "(ObjectID > 0)"
            Logger.debug(query_string)

            query                        = RallyAPI::RallyQuery.new()
            query.type                   = opts[:type]
            query.fetch                  = fetch
            query.project_scope_up       = opts[:projectScopeUp] || false
            query.project_scope_down     = opts[:projectScopeDown] || false
            query.page_size              = 200 #optional - default is 200
            query.limit                  = 200000 #optional - default is 99999
            query.query_string           = query_string

            emit :batch_toolkit_begin, opts[:type]
                # Query Rally
                query_results = rally_api.find(query)

                ret = {'Results' => query_results}
            emit :batch_toolkit_end, opts[:type]

            ret
        end
	end
end
