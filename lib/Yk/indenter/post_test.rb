
class Token
	
	module PostTestDo

		def postTestFinalize pi
			if !requireArg?
				raise Error.new("descrepant post test clause")
			end
			@argEnd = pi
			closeSentence pi
			(d = (w = pi.parent).wrapped.orgEntity).iteratorCand = nil
			toReplace = "break " + case w.str
			when "while"
				"unless "
			when "until"
				"if "
			end
			Token.addMod w.range, toReplace
			if (v = d.dnext).kind == :on_symbeg && label = v.var_label
				d.defClsFirstSententence.first.setIteratorLabelVar label
				Token.addMod d.range, 
					"begin
						#{label} = ItratorLabel.new
						while true
							begin
								#{label}.setLast((".gsub(/\n/, ";").gsub(/\s+/, " ")
				res =			"))
							rescue #{label}.exNext
								next
							rescue #{label}.exRedo
								redo
							end
						end
						#{label}.res #nil or something in case iterator
					rescue #{label}.exBreak
						#{label}.res
					end".gsub(/\n/, ";").gsub(/\s+/, " ")
			else
				Token.addMod d.range, "while true;" # "do" -> "while true;"
				res = ";end;"
			end
			pi.spop
			Token.addMod pi.ipos, res
		end
	
	end
end
