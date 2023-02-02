class String
	undef gets
	def posReplaceSpace range
		range.first
	end
	def posOf expr, from
		x, y = from[1], from[0] - 1
		lns = expr.lines
		after = lns[y .. -1].join[x .. -1]
		i = after.index expr
		if i
			lns = expr
		else
			nil
		end
	end
end


class Module
	def attr_accessor_predicate *args
		args.each do |e|
			d = %{
				def #{e}= arg
					@#{e} = arg
				end
				def #{e}?
					arg
				end
				def #{e}
					arg
				end
			}
			case self
			when Class
				class_eval d
			when Module
				module_eval d
			end
		end
	end
end


require 'ripper'


class Ripper::Lexer::State
	List = %i{
		BEG
		END
		ENDARG
		ENDFN
		ARG
		CMDARG
		MID
		FNAME
		DOT
		CLASS
		LABEL
		LABELED
		FITEM
	}
	List.each_with_index do |s, i|
		self.class_eval %{
			def #{s.to_s.downcase}?
				if (1 << #{i}) & (to_i.to_i + 0) != 0
					self
				else
					nil
				end
			end
		}
	end
end


class << Ripper
	STUFFER1 = "\v\f\v\f\v\f"
	STUFFER2 = "\v\v\v\f\f\f"
	alias_method :org_lex, :lex
	def lex src, *args, **opts
		res = nil
		rlst = []
		llcor = nil
		begin
			class << src
				alias_method :org_respond_to?, :respond_to?
				def respond_to? label
					if label == :gets
						return false
					else
						org_respond_to? label
					end
				end
			end
			res = catch :restart do
				llst = org_lex src, *args, **opts
				i_pos = 0
				pe = nil
				lcor = nil
				llst.each do |e|
					i_pos += e[2].size
					if !llcor || (llcor[0] < e[0][0] || (llcor[0] == e[0][0] && llcor[1] <= e[0][1]))
						if define?(Endless) && e[1] == :on_sp && e[2][0] == "\\" && (!pe || pe[2] !~ /#{Token.stuffer(:hidden_nl)}$/)
							ex = [[e[0][0], e[0][1] + 1], e[2][1..-1] == "\n" ? :on_nl : :on_sp, e[2][1..-1], Ripper::Lexer::State.new(1)]
							e = [e[0], :on_op, "\\", Ripper::Lexer::State.new(1)]
						elsif e[1] == :on_CHAR && 
							if e[2] == "\\"
								e[1] = :"\\"
								e[3] = Ripper::Lexer::State.new(1)
							elsif e[2] == "\\\t"
								e[1] = :"\\"
								e[2] = :"\\"
								e[3] = Ripper::Lexer::State.new(1)
								ex = [[e[0][0], e[0][1] + 1], :on_sp, "\t", Ripper::Lexer::State.new(1)]
							end
						end
						rlst.push e
						rlst.push ex if ex
					end
					lcor = e[0].clone
					lcor[1] = e[0][1] + e[2].size
					pe = e
				end
				if src.size > i_pos
					loop do
						if src[i_pos .. -1] =~ /\A[\r \f\v]+/
							rlst.push [lcor.clone, :on_sp, $&, Ripper::Lexer::State.new(1)]
							lcor[1] += $&.size
							i_pos += $&.size
						elsif src[i_pos] == "\n"
							rlst.push [lcor.clone, :on_nl, "\n", Ripper::Lexer::State.new(1)]
							lcor[0] += 1
							lcor[1] = 0
							i_pos += 1
						else
							break
						end
					end
					llcor = lcor
					src = "\n" * (lcor[0] - 1) + " " * lcor[1] + src[i_pos .. -1]
					throw :restart, :restart
				end
			end
			#p res
		end while res == :restart
		rlst
	end
end


class Module
	def ___call_overridden

	end
	def self.override_method new, old

	end
end



class Token
	attr_accessor :pos, :str, :stat, :first, :tty_pos, :prevNL
	attr_reader :kind, :dprev
	attr_accessor :dnext,
				:parStackI,
				:beginner, :parent,
				:params, :cur
	ModuleList = {}
	def self.registerModule mod, kind
		ModuleList[kind] = true
	end
	def self.getModule kind
		ModuleList[kind] || (
			k = k.to_s.gsub /(\A|_)[a-z]/ do
				($&[1] || $&[0]).upcase
			end
			eval("defined?(#{k}) && #{k}.is_a?(Module) && #{k}")
		)
	end
	def onClassify
	end
	def classify
		mod = self.class.getModule @kind
		extend mod if mod
		@classified = true
		onClassify
	end
	def prev
		dp = @dprev
		until dp&.kind != :on_sp
			dp = dp.dprev
		end
		return dp
	end
	def prev_non_sp
		dp = @dprev
		until dp&.kind != :on_sp && !SameAsLn.include?(dp.kind)
			dp = dp.dprev
		end
		return dp
	end
	def kind= k
		@kind = k
		if @classified
			classify
		end
	end
	def dprev= arg
		@dprev = arg
		arg.dnext = self
	end
	def initialize po, k, st, sta, i, t, pr
		# [po, k, st, star] <= Ripper.lex.each do |[[Integer, Integer], Symbol, String, Ripper::Lexer::State]|
		@pos = po
		@kind = k
		@str = st
		@stat = sta
		@first = i
		@tty_pos = t
		@prevNL = pr
	end

	class Params < Struct.new(:dprev, :parStack, :idtStacks, :idtStack)
		def initialize o
			@parStack = [o.wrapped]
			@idtStack = []
			@idtStacks = []
			@dprev = o
		end
	end
	@@cur = Params.new Origin
	@@hdocs = HDocStack.new
	@@curHDocStack = []
	class HDocStack < Array
		def hDocBeginIndex
			llno = last.lno
			i = 0
			reverse_each do |t|
				if llno != t.lno
					break
				end
				i -= 1
			end
			i
		end
		def hDocBegin
			self[hDocBeginIndex]
		end
		def sliceHDocBegin!
			i = hDocBeginIndex
			ret = self[i]
			delete_at i
			ret
		end
	end
	def self.curHDoc
		@@curHDocStack.last
	end
	def self.curSetHDocBegin
		@@hdocs.last.params ||= @@cur
		hDocBeg = @@hdocs.hDocBegin.cloneBase
		@@curHDocStack[-1] = hDocBeg
		@@cur = Params.new hDocBeg
		@@cur.dprev = hDocBeg
		@@cur.parStack = [hDocBeg.wrapped]
		@@cur.idtStacks = []
		@@cur.idtStack = []
	end
	def parentHasPeriodClause
		eachParent do |t|
			case t.kind
			when :on_period, :"&."
				return true
			when :on_lbrace
				return true if t.inserted?
			end
		end
		return false
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
	def isOperand? checkParent = true
		case @kind
		when :on_period
			if !checkParent || parentHasPeriodClause
				@prev.isStarter?
				|| @prev.isPreOp? 
				|| [:on_lparen, :on_lbrace, :on_lbracket, :on_comma, :on_semicolon].include?(@prev.kind) 
				|| [:on_ident, :on_const].include?(@prev.kind) && @dprev != @prev # @dprev == :on_sp
			else
				false
			end
		when :on_lparen
			![:on_comma, :"::"].include?(@prev.kind) && (![:on_ident, :on_const].include?(@prev.kind) || @dprev != @prev)
		when :on_lbracket # cannot use for "x [1] do ... end" ; when x is a variable, is not operand, when x is a method, is operand
			![:on_ident, :on_const].include?(@prev.kind) || @dprev != @prev
		when :on_lbrace # cannot use for "-> a { ... }"
			![:on_ident, :on_const].include?(@prev.kind)
		when :on_rparen, :on_rbrace, :on_rbracket
			false
		else
			if isPreOp?
				(@prev.isStarter? || [:on_lparen, :on_lbrace, :on_lbracket, :on_comma, :on_semicolon].include?(@prev.kind)) &&
					[:on_rparen, :on_rbrace, :on_rbracket, :on_comma, :on_semicolon].include?(@prev.kind)
			elsif @prev.isPreOp?
				true
			else
				false
			end
		end
	end
	LineEnders = [nil, :on_nl, :on_semicolon]
	SpaceOrComment = [:on_sp, :on_nl, :on_comment, :on_ignored_nl, :on_embdoc_beg, :on_embdoc_end, :on_embdoc]
	SameAsLn = [:on_comment, :on_embdoc_beg, :on_embdoc_end, :on_embdoc, :on_ignored_nl]
	StrBegin = [:on_regexp_beg, :on_tstring_beg, :on_qwords_beg,:on_words_beg, :on_symbeg, :on_qsymbols_beg, :on_symbols_beg, :on_backtick]
	def self.next expr, opts, f, lnoBase = 0, ebmode = nil
		if !@@tenum
			@@expr = expr
			@@opts = opts
			@@fName = f
			@@lnoBase = lnoBase
			@@ebmode = ebmode
			tab_stop = opts[:tab_stop]
			llst = Ripper.lex(expr)
			class << llst
				alias_method :org_each, :each
				def each tab_stop
					w_pos = 0
					prevNL = true
					i = 0
					org_each do |e|
						str = e[2]
						e[3] = e[3].to_s.split("|").map{|e|e.intern}
						yield Token.new(*e, i, w_pos, prevNL)
						i += str.size
						if str =~ /(\n|\r)\s*$/
							prevNL = true
						elsif str !~ /^\s*$/
							prevNL = false
						end
						if str[-1] == "\n" || str[-1] == "\r"
							w_pos = 0
						else
							lnpos = str.rindex(/\n|\r/)
							begin
								require 'Yk/tty_width.rb'
								if lnpos
									w_pos = TTYWidth.width str[lnpos + 1 .. -1], tab_stop, 0
								else
									w_pos = TTYWidth.width str, tab_stop, w_pos
								end
							rescue ArgumentError
								w_pos = -1
							end
						end
					end
				end
			end
			# 後置の'は、プロパティ
			# a.{. + 1}                              /* '.' is self */
			# (a, b, c).{.aFunc + .bFunc + .cFunc}   /* cannot use '.' */
			# (a, b, c)::{aFunc + bFunc + cFunc}
			# \\ a + 1, b + 2, x = c + 3 /* \\で変数を定義可能なclause */
			#		_1 + _2 + x
			prevLnFirstPos = 0
			enum = Enumerator.new llst, :each, tab_stop
			@@tenum = Enumerator.new do |y|
				checkIsIdent = -> t do
					if t.dprev&.kind == :on_symbeg
						t.kind = :on_tstring_end
					else
						case t.prev.kind
						when :on_period, :"&.", :"::"
							t.kind = :on_ident
						when :on_op
							if t.str == "&." || t.str == "::"
								t.kind == :on_indent
							end
						else
							if [:def, :undef].include?(t.prev&.kind) ||
							  t.prev&.kind == :on_kw && ["def", "undef"].include?(t.prev&.str) ||
							  t.prev&.kind == :alias ||
							  t.prev&.kind == :on_kw && t.prev&.str == "alias" ||
							  t.prev&.prev&.kind == :alias && t.prev&.prev&.str == "alias"
								t.kind = :on_ident
							end
						end
					end
				end
				normalize = -> t do
					case t.kind
					when :on_ident, :on_const
						if t.dprev&.kind == :on_symbeg
							t.kind = :on_tstring_end
						end
					when :on_kw
						if !checkIsIdent.(t)
							s = t.str.intern
							if Starters.include?(s)
								if !%i{while until rescue if unless}.include?(s) || %i{on_semicolon. on_nl}.include?(t.prev.kind) # modifier
									t.kind = s
								end
							elsif %i{and or not}.include?(s)
								t.kind = s
								t.setOp
							elsif s == :end
								t.kind = s
							end
						end
					when :on_op
						if !checkIsIdent.(t)
							t.kind = t.str.to_sym
							t.setOp
						end
					when :on_backtick
						checkIsIdent.(t)
					end
				end
				queue = []
				begin
					t = nil
					while true
						if t.lno == @@hdocs.last&.lno && t.str =~ /\n/
							@@curHDocStack.push nil
							curSetHDocBegin
						elsif t.kind == :on_heredoc_end
							hDocBeg = @@hdocs.sliceHDocBegin!
							if hDocBeg.str !~ /^\<\<(\~|\-|)(['"`]|)(.*?)\2/ || t.str !~ /^\s+#{Regexp.escape $3}\n/
								raise Error.new("here document '#{hdBeg.str}' is descrepant with '#{t.str.chomp}'")
							end
							if hDocBeg.lno != @@hdocs.last&.lno
								@@cur = hDocBeg.params
								@@curHDocStack.pop
							else
								curSetHDocBegin
							end
						else
							@@cur.dprev = t
						end
						t = enum.next
						t.cur = @@cur
						if t.kind == :on_heredoc_beg
							@@hdocs.push t
						end
						t.dprev = t.cur.dprev
						case t.kind
						when :on_embexpr_beg
							t.cur.idtStacks.push t.cur.idtStack
							t.cur.idtStack = []
						when :on_embexpr_end
							t.cur.idtStack = t.cur.idtStacks.pop
						end
						# setup first indent
						if t.realToken?
							if t.prev == :origin
								if defined?(Endless) && t.tty_pos != 0
									raise Error.new("first word should not have space before it")
								else
									t.ipush
								end
							elsif t.prev == :on_embexpr_beg
								t.tty_pos = 0
								t.ipush # not spush, "str#{ goo ..." : tty_pos of 'goo' = 0
							elsif t.prev_non_sp == :origin
								if defined?(Endless) && t.tty_pos != 0
									raise Error.new("first word should not have space before it")
								else
									t.ipush
								end
							elsif t.prev_non_sp == :on_embexpr_beg # "set#{              #
								t.ipush                        #          goo        # ipush:'goo' thereafter (not here)
							end
						end

						if t.kind == :on_comment # bare for adhoc literals
							checkExtendedEmbExpr t.first + 2 if AdhocLiterals[:path] || AdhocLiterals[:url] || AdhocLiterals[:email]
						end
						if SameAsLn.include? t.kind
							t.kind = :on_nl
						end
						# 2nd :on_nl is :on_sp
						if t.prev.kind == :on_nl && t.kind == :on_nl
							t.prev.kind = :on_sp
						end
						indentMode = nil
						if t.realToken? && (%i{on_nl origin on_embexpr_beg}.incluide?(t.prev.kind))
							indentMode = prevLnFirstPos <=> t.first
							prevLnFirstPos = t.first
							if defined?(Endless)
								if t.kind == :ident && t.str == "_"
									if indentMode == 1 # indent out
										t.kind = :continue_clause
										t.addMod t.range, " "
									else # t.prev == \n
										t.prev.addMod t.prev.range, "\\\n"
										t.prev.kind = :on_sp
										t.addMod t.range, " "
										t.kind = :on_sp
										t.str = " "
									end
								end
							end
						end
						tpp = t.prev.prev
						if (tpp = t.prev.prev).contOp? # operator before new line
							if indentMode # new line
								if defined?(Endless) && ( # . \n t
								   	defined?(PeriodTheme) && (tpp.kind == :on_period || tpp.kind == :on_op && tpp.str == "&.") ||
									defined?(DColonTheme) && (tpp.kind == :on_op && tpp.str == "::") )
										if tpp.dprev.terminal? # foo. \n t
											case indentMode
											when 0 #same level
												t.prev.kind = :on_sp
											when -1 #indent out
												raise Error.new("cannot continue '#{tpp.str}'")     # error
											end
										elsif tpp.str == "&." # foo &. \n t
											raise Error.new("cannot use '&.' as operand")    # error
										end
								elsif !defined?(PeriodTheme) || tpp.kind != :on_period || !tpp.dprev.terminal? # foo . \n
									t.prev.kind = :on_sp
								end
							end
						end
						normalize.(tpp)
						if indentMode
							if !defined?(Endless)
								if tpp.kind == :on_kw && %w{class module def while until if elsif alias undef}.include?(tpp.str)
									t.prev.kind = :on_sp
								end
								if tpp.prev.kind == :on_kw && tpp.str == "alias"
									t.prev.kind = :on_sp
								end
								if !defined?(FreeCase)
									if tpp.kind == :on_kw && %w{when in for}.include?(tpp.str)
										t.prev.kind = :on_sp
									end
								end
								if !defined?(ArglessCase)
									if tpp.kind = :on_kw && tpp.str == "case"
										t.prev.kind = :on_sp
									end
								end
							end
						end
						t.prev_non_sp.prev_non_sp.setGo
						queue.push t
						while !queue.empty?
							qf = queue.first
							break if !qf.go?
							y << queue.shift
						end
					end
				rescue StopIteration
					while !queue.empty?
						qf = queue.first
						normalize.(qf)
						y << queue.shift
					end
				end
			end
		end
		res = @@tenum.next
		res.parent = res.cur.parStack.last.entity
		res.classify
	end

	require 'Yk/indenter/each_token'

	Starters = %i{
		begin
		do
		else
		ensure
		then
		rescue
		case
		def
		class
		module
		if
		elsif
		unless
		when
		in
		until
		while
		free_case
		free_in
		for
		free_when
		loop_for
	}
	StartersMayBrace = %i{
		on_tlambda
		\\
		on_nl
		::
		on_period
		&.
	}
	StartersStr = %i{
		on_regexp_beg
		on_tstring_beg
		on_qwords_beg
		on_words_beg
		on_symbeg
		on_qsymbols_beg
		on_symbols_beg
		on_backtick
		on_heredoc_beg
	}
	def classifyBeginner
		class.implementBginner self
		if Starters.include? @kind
			class.implementStarter self
		end
		if StartersStr.include? @kind
			class.implementStarterStr self
		end
		if StartersMayBrace.include? @kind
			class.implementStarterMayBrace self
		end
		if [:on_lparen, :on_lbrace, :on_lbracket].include? @kind
			class.implementOpener self
		end
		classify
	end
	def setComma t
		########
	end
	Sentence = Struct.new(:first, :last)
	def self.implementBeginner obj
		class << obj
			attr_reader :ender, :sentences, :idt
			attr_writer :wrapped
			def wrapped
				@wrapped ||= Wrapper.new(self)
			end
			def spop
				w = cur.parStack.pop # wrapped
				w.orgEntity.idt.popsi w
				w.orgEntity.setEnder self
			end
			def openSentence t
				if requireArg?
					(@args ||= []).push Sentence.new(t, nil)
				else
					(@sentences ||= []).push Sentence.new(t, nil)
					if @kind == :case
						if ![:when, :in].include? t.kind
						########	self.kind = :free_case
						end
					end
				end
			end
			def lines
				if !@lines && @sentences
					@lines = [@sentences[0].first ... nil]
					@sentences.each do |e|
						if @lines[-1].last
							@lines.push(e.first ... nil)
						end
						if e.last.kind == :on_nl
							@lines[-1].last = e.last
						end
					end
				end
				@lines
			end
			def closeSentence t
				if requireArg?
					if @args[-1].last
						raise Error.new("argument of '#{str}' is already closed")
					end
					@args[-1].last = t
				else
					if @sentences[-1].last
						raise Error.new("sentence is already closed")
					end
					@sentences[-1].last = t
				end
			end
			def lastSentenceEnd
				@sentences[-1].last
			end
			def isSentenceHead?
				@parent.senteces.each do |s|
					if s.first == self
						return true
					end
				end
				false
			end
			attr_accessor :inserted
			def inserted?
				@inserted
			end
		end
	end
	def spush
		classifyBeginner
		cur.parStack.push wrapped
		cur.idtStack.last.pushsi wrapped
		@idt = cur.idtStack.last
	end
	def reserve_spush
		@sop = :spush
	end
	def reserve_spop
		@sop = :spop
	end
	def doSop
		case @sop
		when :spush
			spush
		when :spop
			spop
		end
	end
	def self.implementStarterStr obj
		(class << obj; self; end).class_eval do
		end
	end
	def isStarter?
		false
	end
	def isStarterMayBrace?
		false
	end
	def isStarterAll?
		false
	end
	def self.implementStarter obj
		class << obj
			def isStarter?
				true
			end
			def isStarterAll?
				true
			end
			attr_reader :argEnd, :in, :do
			attr_accessor :body
			def argEnd
				if @argEnd
					@argEnd
				elsif @kind == :do || @kind == :on_lbrace
					if (n = next_non_sp).kind == :|
						n.ender.dnext
					else
						@dnext
					end
				end
			end
			def argEnd= t
				@argEnd ||= t
			end
			def closeBeginner pi
				"end"
			end
			def thenRelated? t
				if [:if, :elsif, :rescue, :unless, :when, :in].include?(@kind)
					if @argStarted
						(@argEnd == t && t.kind == :on_semicolon || @argEnd.kind == :on_nl)
					end
				end
			end
			def doRelated?
				!@do && @argStart && ([:while, :until].include?(@kind) || (@kind == :for && @in))
			end
			def clauseWhen t
				case @kind
				when :when
					if !@argEnd
						raise Error.new("when cluase without '#{@kind}' arguments or semicolon, new line")
					end
				when :case
					if !@argStart
						raise Error.new("when cluase without '#{@kind}' arguments")
					end
					@argEnd ||= t
				end
				@wrapped.changeEntity t
			end
			def clauseIn t
				case @kind
				when :when
					if !@argEnd
						raise Error.new("when cluase without '#{@kind}' arguments or semicolon, new line")
					end
				when :case
					if !@argStart
						raise Error.new("when cluase without '#{@kind}' arguments")
					end
					@argEnd ||= t
				end
				@wrapped.changeEntity t
			end
			def clauseRescue t
				case @kind
				when :def, :class, :module, :rescue
					if !@argEnd
						raise Error.new("else cluase without '#{@kind}' arguments or semicolon, new line")
					end
				when :begin
				end
				@wrapped.changeEntity t
			end
			attr_accessor :in
			def setIn t
				@in = t
				t.kind = :loop_for_in
				t.in = t # case in has no @in
				@argEnd = t # range not include end
				@wrapped.changeEntity t
			end
			def clauseElse t
				if requireArg?
					raise Error.new("else cluase without '#{@kind}' arguments or semicolon, new line")
				end
				@wrapped.changeEntity t
			end
			def clauseElseIf t
				if requireArg?
					raise Error.new("else cluase without '#{@kind}' arguments or semicolon, new line")
				end
				@wrapped.changeEntity t
			end
			def clauseEnsure t
				(@ensure ||= []).push t
				@argEnd ||= t
				@wrapped.changeEntity t
			end
			def setThen t
				if @then
					raise Error.new("duplicated then")
				end
				@then = t
				@argEnd ||= t
			end
			def setDo t
				if @do
					raise Error.new("duplicated do")
				end
				@do = t
				@argEnd ||= t
			end
			def requireArg?
				!@argEnd
				&& [:def, :class, :module, :if, :elsif, :unless, :case, 
					:when, :in, :until, :while, :rescue, :for, :"\\", 
					:on_tlambda, :post_test_while, :post_test_until, :for, :loop_for, :loop_for_in, :free_in, :free_when, :case, :non_free_case].include?(kind)
			end
			def argRange
				if @argStart && @argEnd
					@argStart.first .. @argEnd.first
				else
					nil
				end
			end
			def mustWithArg?
				[:def, :class, :module, :if, :elsif, :unless, :in, :until, :while, :post_test_while, :post_test_until, :loop_for, :loop_for_in, :free_case].include?(kind)
			end
			def completed?
				!mustWithArg? || @argEnd
			end
			def nativeContinue? t
				if @kind == :on_tlambda && @body == :do
					t.kind == :end
				else
					(t.kind == :end && isStarter?) || (
						case t.kind
						when :else
							%i{rescue elsif if unless when in then ifless_then ifless_elsif}.include? @kind
						when :when
							%i{when case}.include? @kind
						when :in
							%i{in case}.include? @kind
						when :rescue
							%i{begin def class module}.include? @kind
						when :ensure
							%i{begin def class module rescue}.include? @kind
						when :elsif
							%i{if elsif then ifless_then ifless_elsif}.include? @kind
						when :post_test_while, :post_test_untl
							@kind == :post_test_do
						end
					)
				end
			end
			#def setPostTest t
			#	if @kind != :do
			#		raise Error.new("not do")
			#	else
			#		@wrapped.changeEntity t
			#	end
			#end
			def isIflessStarter?
				[:then, :elsif, :else, :ifless_then, :ifless_else, :ifless_elsif].include?(@wrapped&.orgEntity&.kind || @kind)
			end
			def continuedClause?
				@parent.nativeContinue?(self) && (!defined?(Endless) || @cur.idtStack.last == @parent)
			end
			def addChild t
				(@children ||= []).push t
			end
			attr_accesor :upperCaseClause
			def trySetUnderCase
				if defined?(FreeCase)
					f = eachParent do |par|
						if [:case, :free_case].include? par.kind
							@case = par
							break :found
						end
					end
					return false if f != :found
					eachParent do |par|
						if [:when, :in, :for, :free_when, :free_in, :free_case].include?(par.kind)
								|| par.kind == :else && par.wrapped.orgEntity == @freeCase
							if !par.argStart
								if !@argStart
									raise Error.new("argless '#{str}' under argless '#{par.str}'")
								elsif par != parent
									raise Error.new("argless '#{par.str}' do not allow '#{str}' clause enclosed by '#{parent.str}...#{parent.ender.str}'")
								end
							end
						end
						par.addChild self
						@upperCaseClause = par
						return true
					end
					return false
				end
				raise Error.new("cannot find upper free case clause")
			end
			def case
				if !@case
					oe = wrapper.orgEntity
					return oe if oe.kind == :case
				end
				return nil
			end
			def spVarName
				##################
			end
			def argCommas
				###############
			end
			def setComma t
			end
			def eachArgs
				##################
			end
			def requireIfConversion?
				@requireIfConversion
			end
			def isWhenCondLBrace?
				@isWhenCondLBrace
			end
			def hasAndOp?
				@hasAndOp
			end
			def inDirectParen?
				@prev_non_sp.kind == :on_lparen && @next_non_sp.kind == :on_rparen
			end
			def checkAndOp
				if hasAndOp? && !@andOpProcessed && !inDirectParen? && %i{on_ident on_const ' "}.include?(dprev)
					Token.addMod tb.last, "("
					Token.addMod t.first, ")"
					@andOpProcessed = true
				end
			end
			attr_accessor :hasAndOp, :andOpProcessed
			attr_accessor :ifConverted
			attr_writer :isWhenCondLBrace
		end
	end
	def var_able?
		[:on_const, :on_ident, :on_tstring_end].include?(@kind) && @str =~ /\a#{VAR_REG}\z/
	end
	def var_label
		(@kind == :on_symbeg && @str =~ /\a:(#{VAR_REG})\z/) ? $1 : nil
	end
	def terminal?
		!isPreOp?
		&& !%i{on_lparen on_lbrace on_lbracket on_period on_comma on_semicolon on_sp on_nl}.include?(@kind)
	end
	def self.implementStarterMayBrace obj
		class << obj
			def isStarterMayBrace?
				true
			end
			def isStarterAll?
				true
			end
			def isStarter?
				false
			end
		end
	end
	def self.implementOpener obj
		class << obj
		end
	end
	def cloneBase
		class.new pos, kind, str, stat, first, tty_pos, prevNL
	end
	def lno
		pos[0]
	end
	def tty_pos
		if @kind == :on_embexpr_beg
			0
		else
			@tty_pos
		end
	end
	def range
		@first ... @first + str.size
	end
	def last
		@first + str.size
	end
	attr_accessor :nextClause, :prevClause, :currentClause
	class Wrapper
		def initialize t
			@entity = t
			@orgEntity = t
		end
		def changeEntity t
			@entity.nextClause = t
			@entity.closeSentence t
			t.prevClause = @entity
			@entity = t
			t.wrapped = self
			@orgEntity.currentClause = t
			t.classifyBeginner
		end
		def orgEntity
			@orgEntity
		end
	end
	def prev_nl?
		@prev == :on_nl
	end
	def endClose?
		isStarter? || @body == :do
	end
	def opponent? t
		case kind
		when :on_lparen
			t.kind == :on_rparen
		when :on_rparen
			t.kind == :on_lparen
		when :on_lbracket
			t.kind == :on_rbracket
		when :on_rbracket
			t.kind == :on_lbracket
		when :on_lbrace
			t.kind == :on_rbrace
		when :on_rbrace
			%i{on_lbrace hash_beg lbrace_clause case_cond_lbrace}.include? t.kind
		when :on_embexpr_beg
			t.kind == :on_embexpr_end
		when :on_embexpr_end
			t.kind == :on_embexpr_beg
		when :hash_beg, :lbrace_clause
			t.kind == :on_rbrace
		when :on_tlambda
			if body.kind == :on_lambeg
				t.kind == :on_rbrace
			elsif body.kind == :do
				t.kind == :end
			end
		when :|
			t.kind == :|
		else
			false
		end
	end
	Origin = self.new(nil, :origin, "", 0, -1, 0, false)
	def ipush
		cur.idtStack.push self
	end
	def pushsi w
		(@parStackI ||= []).push w
	end
	def popsi w
		if !@parStackI || @parStackI.empty? || @parStackI.last != w
			raise Error.new("cannot close '#{t.str}' beyond indentation")
		else
			@parStackI.pop
		end
	end
	def isOp?
		@isOp
	end
	attr_writer :go
	def go?
		@go
	end
	def setGo
		t = self
		while t && !t.go?
			t.go = true
			t = t.dprev
		end
	end
	def callArgOp?
		%i{& ** *}.include?(@kind) && dnext.realToken?
	end
	def unary?
		case @kind
		when *%i{:: ! ~ <: @+ @- @! @~ @<:}
			true
		when *%i{+ -}
			if dnext.realToken?
				true
			end
		when :^
			if defined?(PinClassOp) && dnext.realToken?
				true
			end
		end
	end
	def themeLParen?
		@kind == :on_lparen && 
			(@ender.next.kind == :on_period && defined?(PeriodTheme) ||
			@ender.next.kind == :"::" && defined?(DColonTheme))
	end
	def nonBinary?
		%i{~ ! <: @+ @- @! @~ @<:}.include? @kind
	end
	def isPreOp?
		@isOp && !%i{' "}.include?(@kind)
	end
	def contOp? # for preliminal token 
		case @kind
		when :on_op
			if @dprev.kind == :on_symbeg
				return false
			end
			pr = defined?(Endless) ? @prev : @prev_non_sp
			if (pr.kind == :def) || (pr.kind == :on_kw && %w{def alias undef}.include?(pr.str))
				return false
			end
			prp = defined?(Endless) ? @prev.prev : @prev_non_sp.prev_non_sp
			if (prp.kind == :def) || (prp.kind == :on_kw && prp.str == "alias"))
				return false
			end
			if @prev.kind == :on_period
				return false
			end
			return true
		when :on_kw
			if %w{or and not}.include? @str
				return true
			end
		when :on_period
			return true
		end
	end
	def setOp
		@isOp = true
	end
	def continues?
		isPreOp?  || 
			[:on_comma, :on_lbrace, :on_lbracket, :on_lparen].include?(kind) || 
			@kind == :on_kw && ["and", "not", "or"].include?(str) || 
			@kind == :on_period && !%i{on_sp on_nl}.include?(@dprev.kind)
	end
	def realToken?
		![:on_sp, :on_nl, :on_heredoc_end, :on_tstring_content, :on_ignored_sp, :on_embexpr_beg, :on_embexpr_end].include?(@kind)
	end
	def unindent_pos= pos
		@unindent_pos = pos
	end
	def unindent_pos
		@unindent_pos || @tty_pos
	end
	def self.stuffer arg
		d = Marshal.dump(arg)
		sz = d.byte_size
		if sz > 65535
			raise Error.new("cannot encode stuffer object")
		end
		szp = [sz].pack("s*")
		d = szp + d + szp
		s = String.new(capacity: sz * 8 + 4)
		d.each_byte do |b|
			8.times do
				s += if b & 0x1 == 1
						"\v"
					 else
						"\f"
					 end
				b >>= 1
			end
		end
		s
	end
	def setPostStuffer arg
		@@expr[range] = @@expr[range] + STUFFER1 + self.class.stuffer(arg) + STUFFER2
	end
	def setPreStuffer arg
		@@expr[range] = STUFFER2 + self.class.stuffer(arg) + STUFFER1 + @@expr[range]
	end
	def _getStuffer pos, sz
		b = 0
		i = 0
		toLoad = String.new(capacity: sz + 1)
		@@expr[pos, sz * 8].each_char do |c|
			case c
			when "\v"
				b += 1 << (i % 8)
			when "\f"
			else
				raise Error.new("illeagal format for stuffer argument")
			end
			i += 1
			if i % 8 == 0
				toLoad += b.chr
				b = 0
			end
		end
		return Marshal.load(toLoad)
	end
	private :_getStuffer
	def getPostStuffer
		pos = first + str().size
		if @@expr[pos, STUFFER1.size] == STUFFER1
			pos += STUFFER1.size
			sz = @@expr[pos, 2].unpack("s")[0]
			pos += 2
			_getStuffer pos, sz
		end
	end
	def getPreStuffer
		pos = first - STUFFER2.size
		if @@expr[pos, STUFFER2.size] == STUFFER2
			pos -= 2
			sz = @@expr[pos, 2].unpack("s")[0]
			pos -= sz * 8
			_getStuffer pos, sz
		end
	end
	#def addLineTop t
	#	(@lineTops ||= []).push t
	#end
	#def addSentenceTop t
	#	(@sentenceTops ||= []).push t
	#	if t.parent != self
	#		raise Error.new("parent of line and sentence, discrepant")
	#	end
	#end
	def parentKind k
		eachParent do |par|
			if par.kind == k
				return par
			end
		end
	end
	def eachParent beyodMethod = false
		if @parent
			yield @parent
			if beyodMethod || ![:class, :module, :def].include(@parent.wrapped.orgEntity.kind)
				@parent.eachParent do |par|
					yield par
				end
			end
		end
		nil
	end
	def defClsFirstSententence
		t = nil
		eachParent do |e|
			t = e
		end
		if t.sentences
			t.sentences[0].first
		else
			raise Error.new("cannot find first sentence")
		end
	end
	def isLineHead?
		par = s.parent
		if par&.args&.find{|e| e.first == self}
			return true
		elsif par&.sentences&.find{|e| e.first == self}
			return true
		end
	end
	def isUnaryOperator?
		@kind == :~ || @kind == :"!"
	end
	attr_accessor :clauseStart
	def iteratorMethod= t
		@iteratorMethod = t
		t.clauseStart = self
	end
	def starterHead= t
		@starterHead = t
		t.clauseStart = self
	end
	def self.addMod pos, str
		(@@modList ||= []).push [pos, str]
	end
	def addMod pos, str
		(@@modList ||= []).push [pos, str]
	end
	def setIteratorLabelVar label
		if (@iteratorLabelVars ||= []).include? label
			raise Error.new("iterator label '#{label}' is already defined.")
		else
			@iteratorLabelVars.push label
			Token.addMod first, "#{label} = nil;"
		end
	end
	def insertVer var, data =  "nil"
		@insertedVar ||= Hash.new
		if !@insertedVar[var]
			@insertedVar[var] = data
			Token.addMod first, "#{var} = #{data};"
		end
	end
	METHOD_TOP = '[^\x00-\x40\x5b-\x5e\x60\x7b-\x7f]'			#exclude numeric and operators
	MED_CHAR = '[^\x00-\x2f\x3a-\x41\x5b-\x5e\x60x7b-\x7f]'	#exclude operators
	VAR_TOP = '[^\x00-\x60\x7b-\x7f]'			#exclude numeric and operators and capitals
	METHOD_REG = "#{METHOD_TOP}#{MED_CHAR}*([?!]|)"
	VAR_REG = "#{VAR_TOP}#{MED_CHAR}*"
	attr_accessor :iteratorCand
	def next_meaningful
		n = self
		begin
			n = n.dnext
		end while n == :on_sp
		n
	end
	def next_non_sp
		n = self
		begin
			n = n.dnext
		end while [:on_sp, :on_nl].include?(n)
		n
	end
	def maybeIteratorLabel? checkAfter = false
		if [:on_label, :on_ident, :on_const].include? kind
			if @@expr[first ... @dnext.last] =~ /\a#{METHOD_REG}:#{VAR_REG}\z/
				if checkAfter
					case (m = @dnext.next_meaningful).kind
					when :on_rparen, :on_rbrace, 
						:on_rbracket, :on_semicolon
					when :on_comma, :^, :"::"
						if [:on_sp, :on_nl].include? m.dprev.kind
							true
						end
					else
						if !m.isPreOp? || m.unary?
							true
						end
					end
				else
					true
				end
			end
		end
	end
	def chunkTop
		##########
	end
	def trySetupIterator mode, doOrBrace, ed = nil
		mthd = trySetupIteratorEach mode
		# while until -> argEnd
		# general -> :do, \\, \n
		#            |a, b, c|の後
		case mthd
		when :hash
		when nil
		else
			label = mthd.label
			if label
				defClsFirstSententence.first.setIteratorLabelVar label
				Token.addMod mthd.chunkTop.first,
					"begin
						#{label} = ItratorLabel.new
					".gsub(/\n/, ";").gsub(/\s+/, " ")
				Token.addMod doOrBrace.argEnd.last,
					"       begin
								#{label}.setLast((".
				gsub(/\n/, ";").gsub(/\s+/, " ")
				ins =
				                                    "))
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
					"end"
			end
		end
		mthd
	end
	def invoker?
		#######
	end
	def trySetupIteratorEach mode
		case mode
		when :forward 		#	while:label 		:while, *on_symbeg, on_tstring_end
			if %i{while until}.include?(@kind)
				if @dnext.kind == :on_symbeg && @dnext.dnext.var_able?
					@label = @dnext.dnext.str
					Token.addMod @dnext.range, ""
				end
				return self
			end
		when :preset
			# foo:label         on_label, *ident
			if var_able? && @dprev.kind == :on_label
				@dprev.label = @str
				Token.addMod @dprev.range, @dprev.str.chop
				Token.addMod range, ""
				return @dprev
			end
			#					*ident, symbeg, tstring_end
			#                   *:'"', symbeg, tstring_end
			if %i{on_const on_ident " '}.include(@kind)
				if @dnext.kind == :on_symbeg && @dnext.dnext.var_able?
					@label = @dnext.dnext.str
					Token.addMod @dnext.range, ""
					Token.addMod @dnext.dnext.range, ""
				end
				return self
			end
		when :back
			# foo:label         on_label, *ident
			if var_able?
				if @dprev.kind == :on_label
					@dprev.label = @str
					Token.addMod @dprev.range, @dprev.str.chop
					Token.addMod range, ""
					return @dprev
			#					ident, symbeg, *tstring_end
			#                   :'"', symbeg, *tstring_end
				elsif @dprev.kind == :on_symbeg && %i{on_const on_ident "}.include(@dprev.dprev.kind)
					@dprev.dprev.label = @str
					Token.addMod @dprev.range, ""
					Token.addMod range, ""
					if @dnext.respond_to? :checkAndOp
						if %i{on_lparen on_lbracket}.include? @dnext.kind
							@dnext.checkAndOp
						end
					end
					return @dprev.dprev
				end
			end
			# foo { } should be hash # {a => b}
			if next_non_sp.kind == :on_lbrace && next.kind == :on_sp
				next_non_sp.kind = :hash_beg
				Token.addMod next_non_sp.range, "Hash.new("
				Token.addMod next_non_sp.next_non_sp.range, ")"
				return :hash
			end
			if %i{on_const on_ident " '}.include(@kind)
				return self
			end
		end
	end
	def setupIteratorLabel
		if @kind == :on_label
			@str = @str.chop
			if @str == "while" || @str == "until" || @str == "do"
				self.kind = @str.intern
			else
				self.kind = :on_ident
			end
			@dnext.kind = :on_symbeg
			@dnext.str = ":" + @dnext.str
		end
		self
	end
	def findParent
		eachParent do |par|
			return par if yield par
		end
		return nil
	end
	def usePeriod?
		##########
	end
end # class Token
class Beginner < Token
	def ender= arg
		@ender = arg
		arg.beginner = self
	end
	attr_accessor :beginner
end
class Opener < Beginner # (, [, { ,| (closeure argument)
end
class Starter < Encloser # if unless case while until
end
