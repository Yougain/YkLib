
class Token
	module OnPeriod
		def onClassify #
			if isOperand? # should not be parent
				if [:on_ident, :on_const].include?(dnext.kind)
					Token.addMod(first, "___theme_by_period")
				elsif ambiguousPeriodTheme?
					raise Error.new("Nested theme is referenced by single '.'")
				else
					Token.addMod(range, "___theme_by_period")
				end
			end
		end
	end
end
