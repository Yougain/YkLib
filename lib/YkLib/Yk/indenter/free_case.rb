
class Token

	MethodChain.override do
		def checkRequireArgStarterWithoutArg
			begin
				super
			rescue WhenWithoutArg => e
				if !parent.trySetUnderCase
					raise e
				end
			end
		end
		def checkRequireArgStarterWithArg
			begin
				super
			rescue ForWithoutIn => e
				if trySetUnderCase
					kind = :for_when
				else
					raise e
				end
			end
		end
	end

	Modules :OnNl, :OnSemicolon do
		MethodChain.override do
			def onClassify
				begin
					super
				rescue ForWithoutIn => e
					if !parent.trySetUnderCase
						raise e
					end
					parent.kind = :for_when
				end
			end
		end
	end

	Modules :OnLbrace do
		MethodChain.override do
			def onClassify
				condKinds = [:when, :for, :free_when, :for_when]
				if condKinds.include?(parent.kind) && (condKinds + [:on_comma]).include(prev.kind)
					kind = :case_cond_lbrace
				else
					super
				end
			end
		end
	end

	Modules :In, :When do
		MethodChain.override do
			def onClassify
				begin
					super
					@case = @wrapper.orgEntity
					@direct = true
					@case.addChild self
					@upperCaseClause = @case
				rescue OrphanContClause => e
					if prev_nl? && trySetUnderCase
						kind = "free_#{@kind}".intern
						spush
					else
						raise e
					end
				rescue ForWhen => e # "for when", "for in"
					parent.kind = "for_#{@kind}".intern
					if !parent.trySetUnderCase
						raise e
					end
					kind = :on_sp
					str = " " * str.size()
				end
			end
		end
	end


	class CaseCondList
		def initialize vn, cn
			@vn = vn
			@cn = cn
			@list = []
		end
		def add c
			@list.push c
		end
		def head
			<<~Out
				#{@vn}.pushCondProxy
				begin
					begin
						#{getSubHead}
					rescue #{@vn}.FinishCond
					end
					if #{@vn}.hasTrue?
			Out
		end
		def getSubHead
			emb = ""
			@list.each do |e|
				if e.is_a? CaseCondList
					emb += e.getSubHead
				else
					case e
					when /\A(when|in)\b/
						emb += <<~Out
									if case #{@vn}.case #{e}; true; else false end
										#{@vn}.pushCond true
										#{@vn}.finishCond
									else
										#{@vn}.pushCond false
									end
								Out
					when /\Afor\b/
						emb += <<~Out
									if case #{@vn}.case when #{$'}; true; else false end
										#{@vn}.pushCond true
									else
										#{@vn}.pushCond false
									end
								Out
					end
				end
			end
			emb
		end
		def tail
			emb += <<~Out
					#{
						if ["when", "in"].include? @cn
							#{@vn}.finish
						end
					}
					end # if #{@vn}.hasTrue?
				ensure
					#{@vn}.popCondProxy
				end
			Out
		end
	end

	def gatherDescendantsCond vn, s, condList
		s.children.each do |e|
			if s != e.parent
				raise Error.new("free case clause '#{e.str}' is not a direct member of argless upper clause, '#{s.str}'")
			end
			if e.argStart # with argument
				###################...................... eの完全な出力結果で置換する
				condList.add @expr[e.first ... e.argEnd.first]
				Token.add e.range,"if #{vn}.shiftCond;"
				pre = "#{vn}.set_res("
				post = ")" + (e.kind != :for_when ? ".finish" : "")
				if e.sentences
					Token.addMod e.sentences[0].first.first, pre
					Token.addMod e.sentences.last.last.first, post
				else
					Token.addMod e.argEnd.first, pre + "nil" + post
				end
				if e.children # still has children
					e.children.each do |ch|
						eachCaseChild(vn, ch, false)
					end
				end
			elsif e.children # argless when, gather conditions from children
				gatherDescendantsCond(vn, s, cnd = CaseCondList.new(vn, e.str))
				condList.add cnd
			else
				raise Error.new("argument less '#{e.str}' under argument less '#{s.str}'")
			end
		end
	end

	def eachCaseChild vn, s, direct # 'when', 'in', 'for' with argument
		if !s.arglessWhen? # argument less when
			if s.children # proxy condition for children
				gatherDescendantsCond(vn, s, cnd = CaseCondList.new(vn, s.str))
				h = cnd.head
				t = cnd.tail
			else # unconditional when, in, for : mimic 'else' of traditional 'case'
				h = "begin;"
				t = "end"
			end
			Token.addMod s.range, h
			Token.addMod s.sentences.last.last, (s.kind != :for_when ? ";#{vn}.finish" : "") + t
		else
			if !direct
				Token.add s.first,"if (case #{vn}.case; "
				if (tmp = case s.kind
							when :for_when
								"when"
							when :for_in
								"in"
							end) then
					Token.add s.range, tmp
				end
				Token.add s.last, "; true; else false; end)"
				pre = "#{vn}.set_res("
				post = ")" + (!tmp ? ".finish" : "")
				if s.sentences
					Token.addMod s.sentences[0].first.first, pre
					Token.addMod s.sentences.last.last.first, post
				else
					Token.addMod s.argEnd.first, pre + "nil" + post
				end
			end
			s.children&.each do |s|
				eachCaseChild(vn, s, false)
			end
		end
	end

	def addChild t
		(@children ||= []).push t
	end

	attr_reader :case
	def direct?
		@direct
	end
	def requireIfConversion?
		@requireIfConversion
	end
	attr_writer :requireIfConversion
	def trySetUnderCase
		f = eachParent do |par|
			if [:case, :non_free_case].include? par.kind
				@case = par
				break :found
			end
		end
		return false if f != :found
		eachParent do |par|
			if [:when, :in, :for_in, :for_when, :free_when, :free_in, :case, :non_free_case].include?(par.kind)
					|| par.kind == :else && par.wrapped.orgEntity == @freeCase
				if par.whenWithoutArg?
					if whenWithoutArg?
						raise Error.new("argless '#{str}' under argless '#{par.str}'")
					elsif par != parent
						raise Error.new("argless '#{par.str}' do not allow '#{str}' clause enclosed by '#{parent.str}...#{parent.ender.str}'")
					end
				end
				par.addChild self
				@upperCaseClause = par
				return true
			end
		end
		return false
	end

	attr_accessor_predicate :caseCondLBraceReplaced

	def whenWithoutArg?
		!@argStart || (dnext&.kind == :> && dnext.dnext&.var_able? && [:on_nl, :on_semicolon].include?(dnext&.dnext&.next&.kind))
	end
	def whenWithVar?
		dnext&.kind == :> && dnext.dnext&.var_able?
	end

	Module :Case, :NonFreeCase do
		def closeBeginner pi
			vn = spVarName
			@direct = true
			children.each do |s|
				if !s.direct? || s.whenWithoutArg? || s.whenWithVar?
					@direct = false
					break
				end
			end
			if @direct
				head = "case(#{vn})"
			end
			Token.addMod range,  "#begin (begin #{vn} = FreeCase.new("
			Token.addMod argEnd.first, "); begin #{head}"
			children.each do |s|
				eachCaseChild(vn, s, @direct)
			end
			tmp = dnext
			while tmp != e
				if tmp.kind == :on_ivar && tmp.str == "@"
					if f = tmp.findParent{[:case, :non_free_case].include(_1.kind)}
						if f == self
							if tmp.parent.kind == :case_cond_lbrace
								if !tmp.parent.caseCondLBraceReplaced?
									Token.addMod tmp.parent.ipos, "->"
									tmp.parent.caseCondLBraceReplaced = tue
								end
								Token.addMod tmp.range, "_1"
							end
								Token.addMod tmp.range, f.spVarName
							end
						end
					end
				else
					Token.addMod tmp.range, "#{vn}.case"
				end
				if %i{case non_free_case}.include? tmp.kind
					tmp = tmp.ender
				else
					tmp = tmp.dnext
				end
			end
			";rescue #{vn}.Finish;ensure #{vn}.pop;end;#{vn}.result);" + "end"
		end
	end


end
