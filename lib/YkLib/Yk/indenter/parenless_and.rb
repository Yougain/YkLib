



attr_accessor_predicate :hasAndOp, :andOpProcessed
def inDirectParen?
	prev.kind == :on_lparen && next.kind == :on_rparen
end

def checkAndOp
	if hasAndOp? && !andOpProcessed? && !inDirectParen? && %i{on_ident on_const ' "}.include?(dprev)
		Token.addMod tb.last, "("
		Token.addMod t.first, ")"
		@andOpProcessed = true
	end
end

Modules :And, :Or, :Not do
	MethodChain.override do
		def onClassify
			super
			if [:on_lbracket, :on_lparen].include?(parent)
				parent.hasAndOp = true
			end
		end
	end
end

Modules :OnRparen, :OnRbracket do
	MethodChain.override do
		def onClassify
			super
			beginner.checkAndOp
		end
	end
end

