require 'rest_client'
require 'base64'
require 'json'
require 'events'

module ArtifactMigration
	class Helper
		extend Events::Emitter
		
		def self.find_workspace(rally, workspace_oid)
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
		
		def self.find_project(rally, workspace, project_oid)
			rally.find_all(:project, :workspace => workspace, :fetch => true).each do |p|
				return p if p.object_i_d == project_oid.to_s
			end
			
			nil
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
	end
end
