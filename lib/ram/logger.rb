module ArtifactMigration
	class Logger
		def self.debug(msg, status = nil)
			Configuration.singleton.loggers.each do |l| 
				if msg.class.ancestors.include? Exception
					l.debug msg.message
					l.debug msg.backtrace
				else
					out = format_msg(msg, status)
					l.debug "#{out}"
				end
			end
		end
		def self.info(msg, status = nil)
			out = format_msg(msg, status)
			Configuration.singleton.loggers.each do |l|
				l.info "#{out}"
			end
		end
		
		protected
		def self.format_msg(msg, status)
			out = msg.to_s + " "
			out += status.rjust(out.to_s.size > 85 ? 3 + status.size : 80 - out.to_s.size, '.') if status
			out
		end
	end
end