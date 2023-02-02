
class Token

	Starters = %i{
		begin
		def
		class
		module
		if
		unless
		loop_for

		ensure
		rescue
		when
		free_in
		free_for
		free_when
	}
	StartersMayBrace = %i{
	}

	def closeBeginner pi
		""
	end

	Modules :Begin, :Def, :Class, :Module, :If, :Unless, :LoopFor do
		def closeBeginner pi
			ins = (requireArg? ? 
				(closeSentence(pi); argEnd = pi; ?;) 
				: ' ') + "end"
		end
	end

	class ForWithoutIn < Exception
		def initialize
			super "new line or semicolon is not allowed after 'for' arguments"
		end
	end

	class WhenWithoutArg < Exception
		def initialize (k)
			super "new line or semicolon is not allowed after '#{k}' arguments"
		end
	end

	class CaseWithoutArg < Exception
		def initialize
			super "missing argment for 'case'"
		end
	end

	module OnSemicolon
		def onClassify
			case parent.kind
			when :on_lbrace
				parent.kind = :lbrace_clause
			end
		end
	end

	module OnNl
		def closeBeginner pi
			c = iteratorMethod
			addModPrev, "do"
			c.trySetupIterator(:preset, self) || "end"
		end
	end

	def checkRequireArgStarterWithoutArg
		case parent.kind
		when *%i{if elsif unless while until on_tlambda post_test_while post_test_until \\ =}
			raise Error.new("missing argument for '#{parent.str}'")
		when :for
			if parent.in
				raise Error.new("missing argument for 'in'")
			end
			raise WhenWithoutArg.new(parent.str)
		when :when
			raise WhenWithoutArg.new(parent.str)
		when :in
			raise Error.new("missing argument for 'in'")
		end
	end

	def checkRequireArgStarterWithArg
		case parent.kind
		when :for
			if !parent.in?
				raise ForWithoutIn.new
			end
		when :on_tlambda
			if !defined?(Endless) || kind == :on_semicolon
				raise Error.new("new line or semicolon is not allowed after '->' arguments")
			end
		when :"=" # for one line method
			spop
		when :post_test_while, :post_test_until
			postTestFinalize self
		end
	end

	Modules :OnSemicolon, :OnNl do
		MethodChain.override do
			def onClassify
				t.parent.closeSentence self
				t.parent.iteratorCand = nil
				begin
					super #raise ForWithoutIn
					if parent.requireArg? # including for, in
						if !parent.argStart
							if defined?(Endless) || kind == :on_semicolon
								checkRequireArgStarterWithoutArg
							end
						else
							checkRequireArgStarterWithArg
						end
					end
				ensure
					parent.argEnd = self # :rescue is unconditionally close argument
				end
			end
		end
	end

	attr_accessor :firstRightAssign
	attr_accessor_predicate :maybeRightMatch
	def addComma t
		(@commas ||= []).push t
	end
	module OnComma
		def onClassify
			if idx = [:on_lbrace, :on_lparen].find_index(parent.kind)
				if !parent.iteratorCand
					parent.addComma self
				end
				if idx == 0
					if parent.firstRightAssign # '=>' as in '{ foo => ...'
						parent.maybeRightMatch = true
					end
				end
			end
			# seup hash
			if parent.kind == :on_lbrace && parent.interatorCand == nil && parent.next.kind == :on_label
				parent.kind = :hash_beg
			end
		end
	end


	def ambiguousPeriodTheme?
		found = false
		eachParent do |t|
			case t.kind
			when :on_period, :"&."
				if (tmp = s.prev).kind == :on_rparen && tmp.beginner.isOperand? && tmp.beginner.multiArgument?
					return true
				end
				found ? return(true) : found = true
			when :on_lbrace
				if t.inserted?
					found ? return(true) : found = true
				end
			end
		end
		return false
	end

	def implementOpener
		.....
	end

	module RightAssignOpn
		::Token.registerModule self, :'=>'
		def onClassify
			# seup hash
			if parent.kind == :on_lbrace && parent.iteratorCand == nil
				if parent.firstRightAssign
					parent.kind = :hash_beg
				else
					parent.firstRightAssign = t
				end
				parent.kind = :hash_beg
			end
		end
	end

	module VerticalBarOp
		::Token.registerModule self, :|
		def onClassify
			if [:do, :on_lbrace].include?(prev) && parent == prev
				if parent == :on_lbrace
					parent = :lbrace_clause
				end
				implementOpener
				reserve_spush
			elsif parent.kind == :|
				reserve_spop
			else
				raise Error.new("unclosed iterator arguments")
			end
		end
	end

	attr_accessor :body
	module OnLambeg
		def onClassify
			if parent.kind == :on_tlambda && !parent.body
				parent.body = self
			end
		end
	end

	Modules :OnLparen, :OnLbracket,
		:OnRegexpBeg, :OnBacktick, :OnEmbexprBeg,
		:OnTstringBeg, :OnQwordsBeg,:OnWordsBeg, :OnSymbeg, :OnQsymbolsBeg, :OnSymbolsBeg do
		def onClassify
			reserve_spush
		end
	end
	Modules :OnRparen, :OnRbracket, :OnRbrace, :OnEmbexprEnd do
		def onClassify
			first = true
			if !parent.opponent?(self)
				toInsert = ""
				while parent.isStarter?
					toInsert = (!parent.requireArg? ? ' ' : ?;) + "end" + toInsert
					reserve_spop
				end
				if !parent.opponent?(self)
					raise Error.new("#{parent.str} is not closed")
				end
				if !toInsert.empty?
					@expr[range] = toInsert + @expr[range]
					raise Restart.new
				end
			end
			reserve_spop
			case @kind
			when :on_rparen, :on_rbracket
				beginner.checkAndOp
			when :on_rbrace
				if @@cur.parStack.size == 0 && RBRACE_MODE.include?(@@ebmode)
					if @@ebmode == :bare
						if AdhocLiterals[:url]
							checkUrl first do |led|
								yield first, :url #back track
							end
						end
						if AdhocLiterals[:email]
							checkEmail first do |led|
								yield first, :email #back track
							end
						end
						if AdhocLiterals[:path]
							checkPath first do |led, pstack|
								yield first, :path, led, pstack #back track
							end
						end
					else
						yield first, @@emode
					end
					# do not return : raise Restart.new
				else
					if beginner.kind == :hash_beg
						beginner.addModPrev, " ("
						addModAfter, ")"
					elsif [:on_lbrace, :lbrace_clause].include? beginner.kind # check iterator
						if [:"&.", :on_period, :"::"].include?((tbp = beginner.prev).kind)
							tbp.closeBeginner self
						else
							case (tt = beginner.prev).kind
							when :on_rparen
								case (ttt = tt.beginner.prev).kind
								when :"&.", :on_period  # foo&.(...){...}, foo.(...){...}
									######## (Table1, Table2)::{....}
									beginner.iterator_method = ttt
									# &.(...){...} -> NG
									# .(...){...} -> OK
								when :"::" #foo::(...){...}
									raise Error.new("foo::(...){...} is not implemented")
								else 
									unless beginner.iterator_method = ttt.trySetupIterator(:back, beginner.argEnd, self) # foo:label(...){...}
										raise Error.new("cannot find iterator method like 'foo' in 'foo(...){...}'") # foo(...){...}
									end
								end
								# foo'(...){...}
								# foo"(...){...}
								# foo."(...)(...){...}
								# .(...){...}
							when :on_rbracket
								beginner.iterator_method = tt.beginner # a[...]{...} ':[]' is iterator method
							else
								beginner.iterator_method = tt.trySetupIterator(:back, beginner.argEnd, self) # foo:label{...}
									raise Error.new("cannot find iterator method like 'foo' in 'foo{...}'") # foo {...}
								end
							end
						end
					end
				end
			end
		end
	end
	module OnHeredocEnd
		def onClassify
			reserve_spop
		end
	end
	SET_LINE = ".__set_line_num__()"
	module OnTstringEnd
		def onClassify
			case parent.kind
			when :on_tstring_beg
				addModAfter SET_LINE
				reserve_spop
			when :on_qwords_beg, :on_words_beg, :on_symbeg, :on_qsymbols_beg, :on_symbols_beg, :on_backtick
				reserve_spop
			else
				raise Error.new("ERROR: String content closing at #{t.pos} is missing beginning\n")
			end
			if cur.parStack.size == 0 && mode.to_s =~ /_quote$/
				yield first # do not return : raise Retart.new
			end
		end
	end
	module OnLabelEnd
		def onClassify
			if parent.kind == :on_tstring_beg
				reserve_spop
			else
				raise Error.new("ERROR: String content closing at #{t.pos} is missing beginning\n")
			end
		end
	end
	module OnRegexpEnd
		def onClassify
			if parent.kind == :on_regexp_beg
				reserve_spop
			else
				raise Error.new("ERROR: Reglar expression closing at #{t.pos} is missing beginning\n")
			end
		end
	end

	module BackSlashOp
		::Token.registerModule self, :"\\" 
		def closeBeginner pi
			c = iteratorMethod
			barg_op = argRange ? "|" : ""
			addModReplace "do #{barg_op}"
			argEnd.addModPrev barg_op
			if c
				ins = c.trySetupIterator(:preset, self) || "end"
			else
				addModReplace " ::Kernel::proc do #{barg_op}\n"
				argEnd.addModPrev barg_op
				ins = "end"
				if isSentenceHead?
					if !argRange
						ins += ".call"
					else
						raise Error.new("orphan proc with argumnents")
					end
				end
			end
			ins
		end
		def checkStarter
			if prev.continues? || isSentenceHead?
				reserve_spush # without method
			else
				if (iteratorMethod = parent&.iteratorCand)&.setupIteratorLabel
					parent.iteratorCand = nil
					reserve_spush
				else
					raise Error.new("cannot find iterator method")
				end
			end
		end
	end

	module OnPeriod
		::Token.registerModule self, :"&.", :"::"
		def themeExpr tk
			case tk
			when :"&."
				"___theme_period"
			when :"::"
				"___theme_double_colon"
			when :on_period
				"___theme_period"
			end
		end
		private :themeExpr
		def closeBeginner pi
			bOpener, bCloser = if pi.kind != :on_rbrace
				"{", "}"
			else
				"", ""
			end
			if prev.kind == :on_rparen && prev.beginner.isOperand?
				if kind == :"&." &&  prev.beginner.multiArgument?
					raise Error.new("multiple theme for &. is not allowed")
				end
				# (Table1, Table2)::\n ... -> ____theme_double_colon___(Table1, Table2){ ... }
				prev.beginner.addModPrev themeExpr(kind)
				addModReplace bOpener
			else # a::\n ...  -> a::____theme_double_colon___{ ... }
				addModAfter, themeExpr(kind) + bOpener
			end
			############ implement ".",  "@foo", "&&"
			ins = bCloser
		end
	end

	module OnTlambda
		def onClassify
			reserve_spush
		end
		def closeBeginner pi
			case @body
			when :on_lambeg
				"}"
			when :do
				"end"
			when nil
				if argEnd != :on_nl
					raise Error.new("descrepant -> args")
				end
				argEnd.addModAfter "{"
				ins = "}"
			end
		end
	end

	module Do
		def onClassify
			if !isOperand?
				t = self
				@parent.instance_eval do
					case @kind
					when :while, :until, :for_in
						if !@do && @argStart
							@do = t
							@argEnd ||= t
							return
						end
					when :on_tlambda
						if !@body
							@body = t
							return
						end
					end
				end
				@iteratorMethod = parent.iteratorCand
			end
			reserve_spush
		end
		def setPostTest t
			@wrapped.changeEntity t
			kind = :post_test_do
			t.kind = ("post_test_" + t.kind.to_s).intern
		end
		def closeBeginner pi
			if c = iteratorMethod
				if parent.iteratorCand == c
					parent.iteratorCand = nil
				end
				c.setupIteratorLabel
				c.trySetupIterator(:preset, self, pi) || "end"
			else
				k = (lop = prev).kind
				if k == :on_rbracket && lop.beginner.prev.terminal? # foo [...] do
					@iteratorMethod = lop.beginner
					"end"
				elsif k == :on_rparen && (tt = lop.beginner.prev).invoker? # foo:label(...), (foo)":label(...), foo'(...)
					tt.trySetupIterator(:back, self, pi) || "end" #tt.dprev = label of foo:label(...)
				else
					ins = "end"
				end
			end
		end
	end

	Modules :While, :Until do
		def closeBeginner pi
			trySetupIterator(:forward, self, pi) || "end"
		end
	end


	def thenRelated? t
		if [:if, :elsif, :rescue, :unless, :when, :in].include?(@kind)
			if @argStarted
				(!@argEnd || @argEnd == t && t.kind == :on_semicolon || @argEnd.kind == :on_nl && @argEnd.prev == t)
			end
		end
	end
	def setThen t
		if @then
			raise Error.new("duplicated then")
		end
		@then = t
		@argEnd ||= t
	end
	class OrphanContClause < ::Exception
		def initialize msg
			super "orphan #{msg}"
		end
	end
	module Then
		def onClassify
			if parent.thenRelated?(prev_non_sp) # prev_non_sp : ';' or '\n'
				parent.setThen self
			else
				raise OrphanContCause.new(str)
			end
		end
	end

	def clauseCont t
		if requireArg?
			raise Error.new("#{t.str} cluase without '#{@kind}' arguments or semicolon, new line")
		end
		@wrapped.changeEntity t
	end
	[:Else, :Elsif].each do |mod|
		%{
			module #{mod}
				def onClassify
					if continuedClause?
						parent.clauseCont self
					else
						raise OrphanContClause.new(str)
					end
				end
			end
		}
	end

	Modules :If, :Unless, :Case, :Module, :Begin, :For, :Def do
		def onClassify
			reserve_spush
		end
	end

	module Class
		def onClassify
			mth = findParent{%i{module class def origin}.include? _1.kind}
			if defined?(Endless)
				n = self.next
			else
				n = next_non_sp
			end
			if (if mth.kind == :def
					n.kind == :<<
				else
					%i{<< on_const ::}.include? n.kind
				end)
			then
				reserve_spush # singleton class
			else # self.class
				kind = :on_ident
				addModPrev "self."
			end
		end
	end

	class ForWhen < Exception
		def initialize arg
			@whenOrIn = arg
			super "'#{arg.str}' is directly placed after 'for'"
		end
	end

	module In
		def onClassify
			if continuedClause?
				t = self
				@parent.instance_eval do
					case @kind
					when :in
						if !@argEnd
							raise Error.new("'in' clause started inside previous 'in' clause without arguments or semicolon, new line")
						end
					when :case
						@kind = :non_free_case
						if !@argStart
							raise Error.new("'in' clause started inside previous 'case' clause without arguments or semicolon, new line")
						end
						@argEnd ||= t
					end
					@wrapped.changeEntity t
				end
			elsif parent.kind == :for && cur.idtStack.last == parent
				if parent.argStart
					parent.argEnd = self
					parent.in = self
					parent.kind = :loop_for
					parent.wrapped.changeEntity self
					@kind = :loop_for_in
				else # for in ....
					raise ForWhen.new(self)
				end
			else
				raise OrphanContClause.new(str)
			end
		end
	end

	module When
		def onClassify
			if continuedClause?
				t = self
				@parent.instance_eval do
					case @kind
					when :when
						if !@argEnd
							raise Error.new("'when' clause started inside previous 'when' clause without arguments or semicolon, new line")
						end
					when :case
						@kind = :non_free_case
						if !@argStart
							raise Error.new("'when' clause started inside previous 'case' clause without arguments or semicolon, new line")
						end
						@argEnd ||= t
					end
					@wrapped.changeEntity t
				end
			elsif parent.kind == :for && cur.idtStack.last == parent && !parent.argStart # for when ....
				raise ForWhen.new(self)
			else
				raise OrphanContClause.new(str)
			end	
		end
	end

	Modules :Rescue, :Ensure do
		def onClassify
			if continuedClause?
				t = self
				@parent.instance_eval do
					case @kind
					when :def, :class, :module, :rescue
						if !@argEnd
							raise Error.new("else cluase without '#{@kind}' arguments or semicolon, new line")
						end
					when :begin
					end
					@wrapped.changeEntity t
				end
			else #independent rescue
				raise OrphanContClause.new(str)
			end
		end
	end

	module NonFreeCase
		def closeBeginner pi
			"end"
		end
	end

	module Case
		def closeBeginner pi
			raise ArgumentError.new("'case' missing 'when' or 'in'")
		end
	end

end

