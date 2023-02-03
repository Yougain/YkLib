

class AdhocLiterals
	class Url
		def initialize arg
			@literal = arg
		end
	end
	def self.__url__ arg
		Url.new arg
	end
end


AdhocLiterals.require 'path'

class GrammerExt
	class Indenter
		URL_HEAD = "AdhocLiterals::__url__("
		def checkURL st
			checkPath st + 1 do |ed, pstack|
				if st + 1 != ed
					if @expr[0..st - 1] =~ /\b[A-Za-z][A-Za-z0-9\.+\-]*$/
						stt = st - (s = $&).size + 1
						if ['"', "'"].include? @expr[st + 1]
							@expr.ssubst stt .. ed, "\"#{s}:\"" + @expr[st + 1 .. ed], :sl_url
						else
							@expr.ssubst stt .. ed, '"' + @expr[stt .. ed] + '"', :sl_url
						end
						raise Restart.new
					end
				end
			end
		end
	end
end