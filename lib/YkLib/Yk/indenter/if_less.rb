
require 'each_token'


class Token
	Modules :Then, :Else, :Elsif, :IflessThen, :IflessElse, :IflessElsif do
		def closeBeginner pi
			if !((ps = parent.sentences)[-1].first != self)
				raise Error.new("'#{str}' without 'if' not registered as sentence in upper clause, '#{parent.str}'")	
			end
			if !ps[-2]
				raise Error.new("'#{str}' without 'if' missing previous line")
			end
			ps[-2].last = nil
			ps.pop
			Token.addMod ps[-2].first.first, "if("
			case @kind
			when :ifless_then, :then
				Token.addMod orgStarter.first, ")"
			when :ifless_elsif, :ifless_else, :elsif, :else
				Token.addMod orgStarter.first, ")then "
			end
			"end"
		end
	end
	[
	 [:Then, :ifless_then]
	 [:Else, :ifless_else]
	 [:Elsif, :ifless_elseif]
	].each do |modName, tk|
		Modules modName do
			MethodChain.override do
				module_eval %{
					def onClassify
						begin
							super
						rescue OrphanContClause => e
							if !prev_nl?
								raise e
							else
								spush
								kind = :#{tk}
							end
						end
					end
				}
			end
		end
	end
end



