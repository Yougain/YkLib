

require 'each_token'


class Token
	module Rescue do
		MethodChain.override do
			def onClassify
				begin
					super
				rescue OrphanContClause => e
					if !prev_nl?
						raise e
					else
						spush
						kind = :independent_rescue
					end
				end
			end
		end
	end
end