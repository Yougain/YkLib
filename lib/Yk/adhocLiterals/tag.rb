class AdhocLiterals
	class Email
		def initialize arg
			@literal = arg
		end
	end
	def self.__email__ arg
		Email.new arg
	end
end


class GrammerExt
	class Indenter
		def checkTag st
			
		end
	end
end