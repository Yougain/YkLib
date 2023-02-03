

require 'each_token'


class Token
	module Ensure do
		MethodChain.override do
			def onClassify
				begin
					super
				rescue OrphanContClause => e
					if !prev_nl?
						raise e
					else
						spush
						kind = :independent_ensure
					end
				end
			end
		end
	end
end