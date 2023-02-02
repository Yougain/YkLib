

class Token
	module ArglessCaseLower
		attr_accessor :arglessCaseUpper

		def addArglessCaseLower pi
			(@arglessCaseLowers ||= []).push pi
			pi.kind = :argless_case_lower
			pi.arglessCaseUpper = self
		end
		def closeBeginner pi
			if !lines
				raise Error.new("empty line under argless case")
			end
			lines.each_with_index do |item, i|
				Token.addMod item.first.first, "#{i == 0 ? "#{')&&(' if parent.kind == :argless_case_lower}(" : ') ||'}("
			end
			#	case  				
			#		x 			    (	x
			#		a 			) ||(	a
			#			b  					)&&(       (  b
			#			c 					       ) ||(  c
			#			d 					       ) ||(  d  )
			#		e           ) ||(	e
			#		f           ) ||(	f                               )
			")"
		end
	end
	module ArglessCase
		def closeBeginner pi
			Token.addMod s.range, ""
			""
		end
	end
	module Case
		MethodChain.override do
			def onClassify
				if [:on_nl, :on_semicolon].include? next.kind
					kind = :argless_case
				end
				super
			end
		end
	end
end