
require 'binding_of_caller'

require 'Yk/indenter/token'

require 'Yk/eval_alt'
require 'Yk/adhocLiterals'


class << self
	alias __org_using__ using
	def using *args
		GrammerExt::using *args
	end
end

module Kernel
	p 123123
	alias __org_require__ require
	module_function
	def require *args #second load
		begin
			p :require, args
			ret = __org_require__ *args
			p :require_finish, args
			ret
		rescue GrammerExt::RequireFinished
			p "finish", args
		end
	end
	def __get_args__ *args, **opts
		args, opts
	end
end

class BasicObject
	def __translate__ expr, f, lno, bl = nil, :mode = :eval, this = nil
		....
		expr
	end
end

class GrammerExt
	class RequireFinished < Exception
	end
	UsedFrom = {}
	def self.usedFrom grammers, f, lno, b
		lns = IO.readlines f
		p [:exec, f, lno + 1]
		p lns[lno + 1 .. lno + 10].join
		mod.doEval(lns[lno + 1 .. -1].join, f, lno + 2)
		p [:exec_finish, f, lno + 1]
		if !(binding.of_caller(2) rescue nil)
			p :exitting
			exit 0
		else
			raise RequireFinished.new("finished")
		end
	end
	def self.using *args, **opts
		args.flatten!
		p :bbbbbbbbbbbb
		b = binding.of_caller(2)
		mods = []
		if !UsedFrom.key? f
			grammers = []
			f, lno = b.source_location
			p [f, lno, :require]
			f = File.expand_path(f)
			lno = lno.to_i - 1
			hasGram = false
			args.each do |arg|
				if arg.is_a?(GrammerExt)
					if !(UsedFrom[f] ||= {}).key? arg
						UsedFrom[f][arg] ||= true
						grammers.push arg
					end
				else
					mods.push arg
				end
			end
			if !grammers.empty?
				lns = IO.readlines f
				p [:exec, f, lno + 1]
				p lns[lno + 1 .. lno + 10].join
				doEval(mods, grammers, opts, lns[lno + 1, -1], f, lno, b)
				if !(binding.of_caller(3) rescue nil)
					p :exitting
					exit 0
				else
					raise RequireFinished.new("finished")
				end
			end
		else
			args.each do |arg|
				if arg.is_a?(GrammerExt)
					if !(UsedFrom[f] ||= {}).key? arg
						raise ArgumentError.new("already used grammer, #{arg.inspect}")
					end
				else
					mods.push arg
				end
			end
		end
		mods.each do |m|
			b.eval("__org_using__ ::ObjectSpace.__id2ref(#{m.__id__})")
		end
	end
	def self.doEval modules, grammers, opts, toEval, f, lno, b
		start = 0
		lns = toEval.lines
		firstLine = lns.shift
		if firstLine !~ /^\s*using\b([^<"'%]*)(#|$)/
			raise ArgumentError.new("using a grammer, cannot contain any literal expressions")
		end
		lns.each_line do |ln|
			#process first using for each GrammerExt
			case ln
			when /^\s*using\b([^<"'%/`]*)(#|$)/
				begin
					args, nopts = TOPLEVEL_BINDING.eval("__get_args__(" + $1 + ")").flatten
					opts.merge nopts
					args.each do |e|
						if e.is_a? GrammerExt
							if !grammers.include? e
								grammers.push e
							end
						else
							if !modules.include? e
								modules.push e
							end
						end
					end
				rescue
					break
				end
			when /^\s*(#|$)/
			else
				break
			end
			start += 1
		end
		toEval = lns[start .. -1].join
		modules.each do |m|
			b.eval("__org_using__ ::ObjectSpace.__id2ref(#{m.__id__})")
		end
		grammers.each do |g|
			toEval = g.translate(opts, toEval, f, lno + start)
		end
		TOPLEVEL_BINDING.eval(toEval, f, lno + start)
	end
	def initialize name
		@name = name
	end
	def inspect
		@name
	end
	def to_s
		@name
	end
end

class Indenter < GrammerExt
	def getTranslateOptions opts
		::AdhocLiterals.resolveRequirement opts
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
	class TranslationError << Exception
	end
	class Restart << Exception
	end
	RBRACE_MODE = StrBegin + [:bare, :path]
	def getOpponent c
		case c
		when ?{
			?}
		when ?[
			?]
		when ?(
			?)
		when ?}
			?{
		when ?]
			?[
		when ?)
			?(
		when ?<
			?>
		when ?>
			?<
		end
	end
	def getLno pos
		@lnoBase + @expr.count_until("\n", pos) 
	end
	def getStringEndExceptSlash pos
		lnoBase = getLno(pos)
		self.class.new @expr[pos .. - 1], @@opts, @@fName, lnoBase, :path_quote do |qed|
			if qed
				return pos + qed
			else
				return nil
			end
		end
	end
	def getClosing pos
		open = @expr[pos]
		close = getOpponent open
		s = 0
		while o = @expr[i]
			case o
			when open #orphan
				s += 1
				break
			when close
				s -= 1
				if s == 0
					return i
				end
			when "#" #embeded expression do not allow first ".", "/", "?", "*", "{}", "[]", otherwise use #wpd{...}, w:wild([],{}.?,*), p:period(.), d:directory(/)
				k = checkExtendedEmbExpr(@@expr, i, :path)
			end
			if !k
				i += 1
			else
				i = k + 1
				k = nil
			end
		end
		return nil
	end
	def getOpening pos
		cl = @expr[pos]
		op = getOpponent cl
		pos -= 1
		cnt = 1
		while pos > 0
			case @expr[pos]
			when cl
				cnt += 1
			when op
				cnt -= 1
				if cnt == 0
					return pos
				end
			when "\n"
				if @expr[0..pos - 1] =~ /#.*$/
				end
			end
			pos -= 1
		end
		nil
	end
	def setRegexp start
		[:f_regexp, :regexp].each do |m|
			testExpr = @expr[start .. - 1]
			self.class.new testExpr, @opts, @fName, getLno(start), m do |red|
				if red
					red += start - 1
					@expr[start .. -1] = REGEXP_HEAD + testExpr[0 .. red] + ")" + testExpr[red + 1 .. -1]
					raise Restart.new
				else
					next
				end
			end
			raise Error.new("#{getLno(start)}: cannot find end of regular expression")
		end
	end
	def checkExtendedEmbExpr start, kind = :bare, til = nil
		sr = til ? @expr[start...til] : @expr
		start = sr.index(/#(([^{\s\\]|\\.)*)\{/)&.+(til ? start : 0)
		if start && checkEmbedPrefix(prefix = $1) && $`[/\\*$/].size % 2 == 0
			lbrace_pos = start + prefix.size + 1
			if @expr[lbrace_pos + 1, EMBED_START.size] != EMBED_START
				altExpr = @expr[lbrace_pos .. -1]
				lnoBase = getLno lbrace_pos
				self.class.new altExpr, @opts, @fName, lnoBase, kind do |ed, mode, led, pstack|
					if ed
						pre = "#{EMBED_START}#{' ' * 6}, '#{prefix}', #{mode.inspect}, ("
						post = "))"
						emb = "\#{" + pre + altExpr[1 .. ed - 1] + post + "}"
						emb[EMBED_START.size + 2, 6] = sprintf('%6d', emb.size)
						@expr[start .. -1] = emb + altExpr[ed + 1 .. -1]
						diff = emb.size - ed + start
						case mode
						when :email
						when :path
							pstack.map!{|e| e + diff}
							checkPrevIsPath nil, start, diff + led, pstack
						when :url
						end
						raise Restart.new
					else
						raise Error.new("#{getLno(start)}: cannot find end of embedded expression")
					end
				end
			else
				if @expr.index /\d+/, lbrace_pos + 1 + EMBED_START.size
					return $&.to_i + start
				else
					raise Error.new("#{getLno(start)}: cannot find length of embedded expression")
				end
			end
		else
			nil
		end
	end
	def removeCComment dprev
		tab_stop = @opts[:tab_stop]
		if @expr.index("*/", dprev.first + 2)
			toReplace = @expr[dprev.first .. til + 1]
			rln_pos = toReplace.rindex("\n")
			begin
				if rln_pos
					@expr[dprev.first .. til + 1] = toReplace.count("\n") * (Token.stuffer(:hidden_nl) + "\\\n") + " " * TTYWidth.width toReplace[rln_pos + 1 .. -1], tab_stop, 0
				else
					@expr[dprev.first .. til + 1] = " " * (TTYWidth.width(toReplace[dprev.first .. til + 1], tab_stop, dprev.tty_pos) - dprev.tty_pos)
				end
			rescue ArgumentError
				if t.prevNL || rln_pos
					raise $!
				else
					@expr[dprev.first .. til + 1] = " "
				end
			end
			raise Restart.new
		else
			raise TranslationError.new("unclosed C-style comment : #{t.str} in #{t.lno}:#{t.cno}")
		end
	end
	EMBED_START = "GrammerExt::__embed__("
	REGEXP_HEAD = "GrammerExt::__regexp__("
	def checkEmbedPrefix pfx
		if pfx == "" || pfx =~ /^\w+$/
			true
		elsif pfx =~ /^\W+$/
			pfin = ""
			pfx.each_char do |c|
				if pfin.index c
					return false
				end
				pfin += c
			end
		else
			false
		end
	end
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
	def initialize expr, opts, f, lnoBase = 0, ebmode = nil
		@lnoBase = lnoBase
		@expr = expr
		@opts = opts
		@fName = f
		case ebmode
		when :f_regexp
			i = 1
			while i = @expr.index(/\/|\#/, i)
				next if $` =~ /\\+$/ && $&.size %  2 == 1
				case @expr[i..-1]
				when /^#(([^{\s\\]|\\.)*)\{/
					begin
						ed = checkExtendedEmbExpr i + $&.size - 1, :on_regexp_beg
						if ed
							i = ed
						end
					rescue Restart
					end
				when /^#.*\n/
					@expr[i] = "\n"
					i = 1
				when /^\/\*.*\*\//m
					@expr[i, $&.size] = " " + "\n" * $&.count("\n")
					i = 1
				when /^\/(\w*)/
					if !$1.include? "x"
						yield nil
					else
						yield i + $&.size - 1
					end
				end
				i += 1
			end
			yield nil #do not return
		when :regexp
			i = 1
			while i = @expr.index(/\/|\#/, i)
				next if $` =~ /\\+$/ && $&.size %  2 == 1
				case @expr[i..-1]
				when /^#(([^{\s\\]|\\.)*)\{/
					begin
						ed = checkExtendedEmbExpr i + $&.size - 1, :on_regexp_beg
						if ed
							i = ed
						end
					rescue Restart
					end
				when /^\/(\w*)/
					yield i + $&.size - 1
				end
				i += 1
			end
			yield nil #do not return
		end
		# tab_stop : 1
		# cjk_width : :mintty, :ms, :xterm
		allTokens = []
		begin
			while true
				t = Token.next expr, opts, f, lnoBase, ebmode
				if t.kind == :/ || (t.kind == :on_regexp_beg && t.str == "/" && (@expr[t.first - REGEXP_HEAD.size, REGEXP_HEAD.size] != REGEXP_HEAD))
					checkPrevIsPath tenum if AdhocLiterals[:path]
					if @expr[t.first + 1] == "*"
						removeCComment dprev if defined?(CComment)
					else
						# regexp
						checkPath t.first if AdhocLiterals[:path]
						# check regexp
						if t.kind == :on_regexp_beg
							setRegexp dprev.first
						end
					end
				end
				
				#if (t.dprev&.dprev&.kind == :on_ident && t.dprev.dprev.maybeItertor? || [:while, :do, :until].include?(t.dprev&.dprev&.kind)) \
				#&& [t.dprev&.kind, t.kind] == [:on_symbeg, :on_ident]
				if AdhocLiterals[:url] || AdhocLiterals[:path]
					if [:on_ident, :on_const].include?(t.dprev&.dprev&.kind) && t.dprev.kind == :on_symbeg && t.realToken?
						checkURL t.dprev.dprev.first if AdhocLiterals[:url] || AdhocLiterals[:path]
					end
					if (t.dprev&.kind == :on_label) && t.realToken?
						checkURL t.dprev.first 
					end
				end
				if AdhocLiterals[:email] && t.dprev&.kind == :on_ivar && t.dprev.dprev&.str !~ /\s/ && (t.dprev.str.size != 1 || @expr[t.dprev&.first + 1] == "[")
					checkEmail t.dprev&.first
				end
				if AdhocLiterals[:tag] && t&.kind == :< && \
					(c = @expr[t.first + 1]; 
							c == ?_ \
						|| c == ?: \
						|| c == ?? \
						|| c == ?! \
						|| ?a.ord <= c.ord && c.ord <= ?z.ord \
						|| ?A.ord <= c.ord && c.ord <= ?Z.ord \
						|| 0x70 < c.ord)
							checkTag(t.first)
				end
				if t.kind == :on_tstring_content
					if mode == :path_quote && t.cur.parStack.size == 1 && t.parent.kind == :on_tstring_beg
						if t.str.include "/"
							raise Error.new("path element cannot contain '/'")
						end
					end
					if t.parent.kind == :on_heredoc_beg && t.parent.str !~ /^\<\<(\~|\-|)'(.+)'$/
						k = t.parent.str =~ /\`/ ? :on_backtick : :on_tstring_beg
					elsif StrBegin.include?(t.parent.kind) && !["'", ":'", "%q", "%w", "%i", "%s"].include?(t.parent.str[0, 2])
						k = t.parent.kind
					end
					ep = t.first
					checkExtendedEmbExpr ep, k, ep + t.str.size
				end
				# concatenate path
				mayConcatenatePath t if AdhocLiterals[:path] || AdhocLiterals[:url]
				# insert embedding information although non-extended embed expression
				if t.kind == :on_embexpr_beg
					checkExtendedEmbExpr t.first, t.parent.kind
				end
				case t.kind
				when :on_heredoc_beg
					t.addModAfter SET_LINE
				end


				# ./file&{.r?}.open
				#	_1.gets
				# braces for hash

				#	foo \n 			\n : pi
				#		goo 		goo : t
				if defined?(Endless) && (pi = t&.prev) == :on_nl && t.realToken?
					ti = t.cur.idtStack.last
					if !ti
						res = 0 <=> t.tty_pos
					else
						if ti.tty_pos < t.tty_pos
							res = -1 # indent-in
						elsif ti.unindent_pos > t.tty_pos
							res = 1
						else
							res = 0 # same 
						end
					end
					if res < 0 # check iterator : indent-in
						s = ti.parStackI&.last&.entity
						case t.prev_non_sp.kind
						when :on_lparen, :on_lbrace, :on_lbracket # t.prev_non_sp == s
						when :"&.", :"::", :on_period #should not be operand, "foo.\n"
							toPush = t.prev_non_sp
						else
							if s&.isStarterAll?
								if s.requireArg? # while if ....
									s.closeSentence pi
								else # if ...;
									# no need
								end
							elsif %i{argless_case_lower argless_case}.include? s&.kind
								s.addArglessCaseLower pi
							else #!s.isStarterAll? # iterator
								if (pi.iteratorMethod = t.parent.iteratorCand)&.setupIteratorLabel
									s.iteratorCand = nil
								else
									raise Error.new("cannot find iterator method for indentation-in")
								end
							end
							toPush = pi # :on_nl, previous line end interpreted as iterator
						end
						if toPush
							toPush.implementStarterMayBrace
							toPush.spush
							t.parent = toPush
						end # toPush is nil : previous line ending with '(\n', '{\n', '[\n'
						t.ipush	#setup indent-in
					else # indent-out or same-level
						toInsert = ""
						seach = proc do |sList, isCurrent|
							sList.each_with_index do |s, i|
								toInsert = s.closeBeginner(pi) + toInsert
								# remove below
								if s.isStarterAll?
									case s.kind
									when :on_nl
										c = s.iteratorMethod
										s.addModPrev, "do"
										if !(ins = c.trySetupIterator(:preset, s))
											ins = "end"
										end
									when :"\\"
										c = s.iteratorMethod
										barg_op = s.argRange ? "|" : ""
										s.addModReplace "do #{barg_op}"
										s.argEnd.addModPrev barg_op
										if c
											if !(ins = c.trySetupIterator(:preset, s))
												ins = "end"
											end
										else
											s.addModReplace " ::Kernel::proc do #{barg_op}\n"
											s.argEnd.addModPrev barg_op
											ins = "end"
											if s.isSentenceHead?
												if !s.argRange
													ins += ".call"
												else
													raise Error.new("orphan proc with argumnents")
												end
											end
										end
									when :"&.", :on_period, :"::"
										if (tmp = s.prev).kind == :on_rparen && tmp.beginner.isOperand?
											if s.kind == :"&." &&  tmp.beginner.multiArgument?
												raise Error.new("multiple theme for &. is not allowed")
											end
											# (Table1, Table2)::\n ... -> ____theme_double_colon___(Table1, Table2){ ... }
											tmp.beginner.addModPrev themeExpr.(s.kind)
											s.addModReplace "{"
										else # a::\n ...  -> a::____theme_double_colon___{ ... }
											s.addModAfter themeExpr.(s.kind) + "{"
										end
										############ implement ".",  "@foo", "&&"
										ins = "}"
									when :on_tlambda
										case s.body
										when :on_lambeg
										when :do
										when nil
											if s.argEnd != :on_nl
												raise Error.new("descrepant -> args")
											end
											s.argEnd.addModReplace s.argEnd.str + "{"
											ins = "}"
										end
									when :do
										if c = s.iteratorMethod
											if s.parent.iteratorCand == c
												s.parent.iteratorCand = nil
											end
											c.setupIteratorLabel
											if !(ins = c.trySetupIterator(:preset, s))
												ins = "end"
											end
										else
											s.addModPrev " ::Kernel::proc "
											ins = "end"
										end
									when :case, :free_case # free case
										ins = finalizeCase(s, pi) + "end"
									else
										if s.isIflessStarter?
											finalizeIfless(s)
											ins = "end"
										elsif ![:until, :while].include?(s.kind) || !(ins = s.trySetupIterator(:forward, s))
											ins = (s.requireArg? ? 
												(s.closeSentence(t.prev); s.argEnd = t.prev; ?;) 
												: ' ') + "end"
										end
									end
									#toInsert = ins + Token.stuffer(:for_indent_out) + toInsert
									toInsert = ins + toInsert
									if isCurrent == :continue_clause
										if !sList[i + 1] || !sList[i + 1].isStarter? || !sList[i + 1].requireArg?
											raise Error.new("cannot continue '#{sList[i + 1].str}'")
										end
										break
									end
								elsif s.arglessCaseUpper
									if !s.lines
										raise Error.new("empty line under argless case")
									end
									s.lines.each_with_index do |item, i|
										item.first.addModPrev "#{i == 0 ? "#{')&&(' if s.kind == :on_nl}(" : ') ||'}("
									end
									#	case  				
									#		x 			    (	x
									#		a 			) ||(	a
									#			b  					)&&(       (  b
									#			c 					       ) ||(  c
									#			d 					       ) ||(  d  )
									#		e           ) ||(	e
									#		f           ) ||(	f                               )
									if s.kind == :argless_case
										s.addModReplace ""
									end
									toInsert = ")" + toInsert
								else
									#if %i{post_test_while post_test_until}.include? (sc = s.currentClause).kind # should be argument is not closed
									#	if !sc.requireArg?
									#		raise Error.new("descrepant post test clause")
									#	end
									#	sc.argEnd = pi
									#	sc.closeSentence
									#	toInsert = postTestFinalize(pi) + toInsert
									#els
									if !isCurrent || isCurrent == :continue_clause
										# if ( { [ left raise error
										raise Error.new("unclosed '#{s.str}' before unindentation")
									else
										break
									end
								end
								pi.spop
							end
						end
						ri = t.cur.idtStack.rindex do |e|
							e.unindent_pos <= t.first
						end
						if !ri
							raise Error.new("unknown error")
						end
						# get indent-in parStack
						chkList = []
						(t.cur.idtStack.size - 1).downto ri - 1 do |i|
							t.cur.idtStack[i].parStackI.reverse_each do |w|
								chkList.unshift w.orgEntity
							end
							t.cur.idtStack.pop
						end

						# get same level parStack
						t.cur.idtStack[ri].unindent_pos = t.first
						t.cur.idtStack[ri].parStackI.reverse_each do |w|
							lastList.unshift w.orgEntity
						end

						seach[chkList, toInsert, false]

						if t.kind == :continue_clause
							seach[lastList, toInsert, :continue_clause]
						else
							case t.cur.idtStack[ri].parStackI.last&.entity
							when ->{_1.nativeContinue?(t.kind)},
 								 ->{ defined?(PostTestWhile) && _1.kind == :do &&
										!_1.parent.iteratorCand &&
										%i{while until}.include?(t.kind) &&
											(_1.setPostTest(t) ; true)          }
								seach[lastList, toInsert, true]
								if t.parent.kind == :on_lbrace && t.kind != :on_rbrace && t.prev_non_sp != t.parent
									t.parent.kind = :lbrace_clause # determine clause, not hash
								end

							end
						end
						if !toInsert.empty?
							pi.addModReplace toInsert + pi.str
						end
					end
					s = t.cur.idtStack.last.parStackI.last.entity #maybe newly pushed
				end
				# free case, free ensure, free rescue, ::{}, .{}
				if [t.prev, t.prev_non_sp].find{[t.parent, t.parent.sentences&.last&.last].include?(_1)} && t.realToken?
					t.parent.openSentence t
				end
				# argless_case
				if %i{on_semicolon on_nl}.include? t.kind # already disposed
					t.parent.closeSentence t
					t.parent.iteratorCand = nil
					if t.parent.kind == :case
						if !t.parent.argStart
							t.parent.kind = :argless_case
						end
					end
				end
				#seup iterator candidate 
				if [:on_ident, :on_const].include?(t.kind) || t.maybeIteratorLabel?
					t.parent.iteratorCand ||= t
				elsif [:"'", :'"'].include?(t.kind)
					if t.parent.iteratorCand == t.dprev
						t.parent.iteratorCand = t
					else
						t.parent.iteratorCand ||= t
					end
				elsif t.kind == :on_rparen && t.beginner.prev.kind == :'."' # ."(method_unbound)
					t.parent.iteratorCand ||= t
				elsif [:on_semicolon, :on_nl, :and, :or, :not].include?(t.kind)
					t.parent.iteratorCand = nil
				elsif t.dprev == t.parent.iteratorCand && t.continues? && !t.nonBinary?
					if t.parent.kind == :on_lbrace && t.kind == :on_comma && t.parent.iteratorCand == nil && 
						(t.parent.next == :on_label || t.parent.next_non_sp == :on_label)
							t.parent.kind = :hash_beg
					end
					if t.parent.kind == :on_lbrace && t.kind == :"=>" && t.parent.iteratorCand == nil
						if t.parent.firstRightAssign
							t.parent.kind = :hash_beg
						else
							t.parent.firstRightAssign = t
						end
						t.parent.kind = :hash_beg
					end
					t.parent.iteratorCand = nil
				elsif t.prev == t.parent.iteratorCand && t.dprev == :on_sp && t.realToken? 
					if t.kind == :on_period && !t.isOperand? || # method call operand start 'iterator.foo'
					   t.continues? && # include :&., :. (non operand) 'iterator +'
						   #(![:"::", :~, :"!", :"<:", :"@+", :"@-", :"@!", :"@~", # unary operator 'iterator ::foo', 'iterator ~foo'
							# :on_lbrace, :on_lbracket, :on_lparen, :"..", :"..."].include?(t.kind) && #'iterator [...]'
							#!([:*, :**, :+, :-, :&].include?(t.kind) && t.dnext != :on_sp) && # another unary operator with post-non-space
							#(!defined?(PinClassOp) || (t.kind == :^ && t.dnext != :on_sp))
						   #)
						   !unary? && !callArgOp? && !t.themeLParen? 
						t.parent.iteratorCand = nil # 'iterator + ...' 'iterator , ...'
					end
				end
				# setup hash
				if t.parent.kind == :on_lbrace && t.kind == :on_comma && t.parent.iteratorCand == nil
					&& (t.parent.next == :on_label || t.parent.next_non_sp == :on_label)
						t.parent.kind = :hash_beg
					end
				if t.parent.kind == :on_lbrace && t.kind == :"=>" && t.parent.iteratorCand == nil
					if t.parent.firstRightAssign
						t.parent.kind = :hash_beg
					else
						t.parent.firstRightAssign = t
					end
					t.parent.kind = :hash_beg
				end

				# instant variable by '>'
				if t.var_able? && (tp = t.dprev).kind == :>
					if tp.dprev.terminal?
						tp.addModReplace "._____insert_var"
						t.addModReplace "(#{t.str} = :#{t.str})"
					elsif [:if, :unless].include? tp.dprev.kind
						tp.addModReplace ""
						t.addModAfter(" = ")
					end
				end
				# instant variable by '>' for when, for
				if %i{when free_when for}.include?((wh = t.parent).kind) && t == wh.argEnd
					if wh.dnext.kind == :> && (whv = wh.dnext.dnext).var_able?
						cs = wh.case
						cs.requireIfConversion = true
						wh.ifConverted = true
						cmp = -> r, ord, head do
							Token.addMod r, head + " _____case_comp_insert_var(#{whv.str} = :#{whv.str}, #{ord}, "
						end
						cmp.(wh.first ... whv.last, 0, "")
						(cms = wh.argCommas).each_with_index do |cm, ord|
							cmp.(cm.range, ord + 1, "), ")
						end
						Token.addMod wh.argEnd.first, ")"
					end
					wh.eachArgs do |a|
						if a.kind == :lbrace_clause || (a.kind == :on_lbrace && a.next.kind != :on_label && a.maybeRightMatch? && a.kind = :lbrace_clause)
							Token.addMod a.first, "->#{a.spVarName}" # dummy argument for lambda
						end
					end
				end
				case t.kind
				when :on_semicolon
					if t.parent.kind == :on_lbrace
						t.parent.kind = :lbrace_clause
					end
				when :and, :or, :not
					if [:on_lbracket, :on_lparen].include?(t.parent)
						t.parent.hasAndOp = true
					end
				when :on_ivar
					if t.str == "@"
						t.eachParent do |par|
							case par.kind
							when :on_lbrace
								if %{for free_when when}.include? par.parent.kind
									if %i{on_comma for free_for free_when when}.include? :on_comma

									end
								end
							when
							if %{case free_case}.include? par.kind

								par.spVarName
							end
						end
					end
				when :on_comma
					case t.parent
					when :on_lparen, :on_lbrace
						if !t.parent.iteratorCand
							t.parent.setComma t
						end
					when :on_lbrace
						if !t.parent.iteratorCand
							t.parent.setComma t
							if t.parent.firstRightAssign
								t.parent.maybeRightMatch = true
							end
						end
					end
				when :on_period
					if t.isOperand? # should not be parent
						if [:on_ident, :on_const].include?(t.next_meaningful.kind)
							Token.addMod(t.first, "___theme_by_period")
						elsif ambiguousPeriodTheme?
							raise Error.new("Nested theme is referenced by single '.'")
						else
							Token.addMod(t.range, "___theme_by_period")
						end
					end
				when :|
					if [:do, :on_lbrace].include?(t.prev_non_sp) && t.parent == t.prev_non_sp
						if t.parent == :on_lbrace
							t.parent = :lbrace_clause
						end
						t.implementOpener
						t.spush
					elsif t.parent.kind == :|
						t.spop
					else
						raise Error.new("unclosed iterator arg")
					end
				when :on_lambeg
					if t.parent.kind == :on_tlambda && !t.parent.body
						t.parent.setBody t
					end
				when :on_lparen, :on_lbracket,
					:on_regexp_beg, :on_backtick, :on_embexpr_beg,
					:on_tstring_beg, :on_qwords_beg,:on_words_beg, :on_symbeg, :on_qsymbols_beg, :on_symbols_beg
					t.spush
				when :on_rparen, :on_rbracket, :on_rbrace, :on_embexpr_end
					first = true
					if !t.parent.opponent?(t)
						toInsert = ""
						while t.parent.isStarter?
							toInsert = (!t.parent.requireArg? ? ' ' : ?;) + "end" + toInsert
							t.spop
						end
						if !t.parent.opponent?(t)
							raise Error.new("#{t.parent.str()} is not closed")
						end
						if !toInsert.empty?
							@expr[t.range] = toInsert + @expr[t.range]
							raise Restart.new
						end
					end
					t.spop
					case t.kind
					when :on_rparen, :on_rbracket
						t.beginner.checkAndOp
					when :on_rbrace
						if t.beginner.kind == :hash_beg
							Token.addMod t.beginner.first, " ("
							Token.addMod t.last, ")"
						end
						if t.cur.parStack.size == 0 && RBRACE_MODE.include?(ebmode)
							if ebmode == :bare
								if AdhocLiterals[:url]
									checkUrl t.first do |led|
										yield t.first, :url #back track
									end
								end
								if AdhocLiterals[:email]
									checkEmail t.first do |led|
										yield t.first, :email #back track
									end
								end
								if AdhocLiterals[:path]
									checkPath t.first do |led, pstack|
										yield t.first, :path, led, pstack #back track
									end
								end
							else
								yield t.first, emode
							end
							# do not return : raise Restart.new
						elsif [:on_lbrace, :lbrace_clause].include? t.beginner.kind # check iterator
							if [:"&.", :on_period, :"::"].include?((tbp = t.beginner.prev).kind)
								tbp.closeBeginner t
								#if (tbpp = tbp.prev).kind == :on_rparen && (tbppb = tbpp.beginner).isOperand?
								#	# foo (a,b,c)::{...} -> foo ___theme(a,b,c){...}
								#	if tbp.kind == :"&." && tbpp.beginner.multiArgument?
								#		raise Error.new("multiple theme for '&.' operator is not allowed")
								#	end
								#	Token.addMod tbppb.first, themeExpr.(tbp)
								#	Token.addMod tbp.range, ""
								#else
								#	# foo(a,b,c)::{...}  -> foo(a,b,c)::___theme{...}
								#	Token.addMod t.beginner.first, themeExpr.(tbp)
								#	# lexical tree analysis with [], ||, &&, ?:, override output
								#end
							else
								case (tt = t.beginner.prev).kind
								when :on_rparen
									case (ttt = tt.beginner.prev).kind
									when :"&.", :on_period  # foo&.(...){...}, foo.(...){...}
										######## (Table1, Table2)::{....}
										t.beginner.iterator_method = ttt
										# &.(...){...} -> NG
										# .(...){...} -> OK
									when :"::" #foo::(...){...}
										raise Error.new("foo::(...){...} is not implemented")
									else 
										unless t.beginner.iterator_method = ttt.trySetupIterator(:back, t.beginner.argEnd, t) # foo:label(...){...}
											raise Error.new("cannot find iterator method like 'foo' in 'foo(...){...}'") # foo(...){...}
										end
									end
									# foo'(...){...}
									# foo"(...){...}
									# foo."(...)(...){...}
									# .(...){...}
								when :on_rbracket
									t.beginner.iterator_method = tt.beginner # a[...]{...} ':[]' is iterator method
								else
									t.beginner.iterator_method = tt.trySetupIterator(:back, t.beginner.argEnd, t) # foo:label{...}
										raise Error.new("cannot find iterator method like 'foo' in 'foo{...}'") # foo {...}
									end
								end
							end
						end
					end
				when :on_heredoc_end
					t.spop
				when :on_tstring_end
					case t.parent.kind
					when :on_tstring_beg
						Token.addmod t.range, SET_LINE
						t.spop
					when :on_qwords_beg,:on_words_beg, :on_symbeg, :on_qsymbols_beg, :on_symbols_beg, :on_backtick
						t.spop
					else
						raise Error.new("ERROR: String content closing at #{t.pos} is missing beginning\n")
					end
					if t.cur.parStack.size == 0 && mode.to_s =~ /_quote$/
						yield t.first # do not return : raise Retart.new
					end
				when :on_label_end
					if t.parent.kind == :on_tstring_beg
						t.spop
					else
						raise Error.new("ERROR: String content closing at #{t.pos} is missing beginning\n")
					end
				when :on_regexp_end
					if t.parent.kind == :on_regexp_beg
						t.spop
					else
						raise Error.new("ERROR: Reglar expression closing at #{t.pos} is missing beginning\n")
					end
				end
				# check Starters status
				h = t.parent
				if h.requireArg?
					if !h.argStart
						case t.kind
						when :on_semicolon, :on_nl
							if defined?(Endless) || t.kind == :on_semicolon
								if h.in
									raise Error.new("missing argument for 'in'")
								else
									case h.kind
									when *%i{if elsif unless while until on_tlambda post_test_while post_test_until \\ =}
										raise Error.new("missing argument for '#{h.str}'")
									when :case
										if !defined?(ArglessCase)
											raise Error.new("missing argument for '#{h.str}'")
										end
									when :for
										if !h.trySetUnderCase
											raise Error.new("new line or semicolon is not allowed after 'for' arguments")
										end
									else
										case h.parent.wrapped.orgEntity.kind
										when :case #traditional case, when, in
											raise Error.new("missing argument for '#{h.str}' of traditional style 'case'")
										when :in, :for, :when # free case when, in, for without argument
										end
									end
								end
							end
							h.argEnd = t # :rescue is unconditionally close argument
						when :in
							if h.kind == :for
								raise Error.new("missing argument for '#{h.str}' before 'in'")
							else # in without for
								h.argEnd = t
							end
						when :on_lambeg, :do
							if h.kind == :on_tlambda
								h.argEnd = t
							end
						when :"=" # one line method # def a(x,y) = x * y
							if defined?(Endless)
								if t.prev.kind == :on_lparen && t.prev.beginner.prev == :def
									h.changeEntity t
								end
							else
								if t.prev_non_sp.kind == :on_lparen && t.prev_non_sp.beginner.prev_non_sp.kind == :def
									h.changeEntity t
								end
							end
						else
							if t.realToken?
								h.argStart ||= t
							end
						end
					else
						if t.kind == :in && h.kind == :for
							h.setIn t #argEnd is also set with this method
						elsif t.kind == :on_semicolon ||  t.kind == :on_nl
							case h.kind
							when :for
								if !t.in?
									if t.trySetUnderCase
										t.kind = :free_for
									else
										raise Error.new("new line or semicolon is not allowed after 'for' arguments")
									end
								end
							when :on_tlambda
								if !defined?(Endless) || t.kind == :on_semicolon
									raise Error.new("new line or semicolon is not allowed after '->' arguments")
								end
							when :"="
								t.spop
							when :post_test_while, :post_test_until
								postTestFinalize t
							end
							h.argEnd = t
						elsif [:when, :in].include?(t.kind) && h.wrapped.orgEntity.kind == :case \ # case foo in goo (same line)
							|| t.kind == :then && [:if, :elsif, :unless, :in, :when, :rescue].include?(h.kind) \
							|| t.kind == :do && \
								(	(h.kind == :for && h.in) \
									|| [:until, :while].include?(h.kind) \
									|| h.kind == :on_tlambda
								)
								h.argEnd = t
						elsif t.kind == :on_lbrace && h.kind == :on_tlambda
							h.argEnd = t
						end
					end
				end
				#check starters
				case t.kind
				when :"\\" #onSetKind
					if t.prev_non_sp.continues? || t.isSentenceHead?
						t.spush # without method
					else
						if (t.iteratorMethod = t.parent&.iteratorCand)&.setupIteratorLabel
							t.parent.iteratorCand = nil
							t.spush
						else
							raise Error.new("cannot find iterator method")
						end
					end
				when :then #checkStarter
					if t.parent&.thenRelated?(t.prev_non_sp)
						t.parent.setThen t
					elsif defined?(Ifless) && defined?(Endless) && t.prev_nl?
						t.spush
						t.kind = :ifless_then
					else
						raise Error.new("orphan then")
					end
				when :on_tlambda #onSetKind
					t.spush
				when :do #onSetKind
					if !t.prev_non_sp.continues? && t.parent&.doRelated?
						t.parent.setDo t
					elsif !t.prev_non_sp.continues? && t.parent.kind = :on_tlambda && !t.parent.body
						t.parent.setBody t
					else
						if !t.prev_non_sp.continues? && !t.isSentenceHead?
							if t.iteratorMethod = t.parent&.iteratorCand
								# omit "t.parent.iteratorCand = nil" 'cause maybe :post_test_while, not iterator
							else
								raise Error.new("cannot find iterator method")
							end
						end
						t.spush
					end
				when :else
					if t.continuedClause?
						t.parent.clauseElse t
					elsif defined?(Ifless) && defined?(Endless) && t.prev_nl?
						t.spush
						t.kind = :ifless_else
					else
						raise Error.new("orphan else")
					end
				when :elsif
					if t.continuedClause?
						t.clauseElsif t
					elsif defined?(Ifless) && defined?(Endless) && t.prev_nl?
						t.spush
						t.kind = :ifless_elsif
					else
						raise Error.new("orphan elsif")
					end
				when :if, :unless, :case, :module, :begin, :for, :def
					t.spush
				when :class
					mth = t.findParent{%i{module class def origin}.include? _1.kind}
					if defined?(Endless)
						n = t.next
					else
						n = t.next_non_sp
					end
					if (if mth.kind == :def
							n.kind == :<<
						else
							%i{<< on_const ::}.include? n.kind
						end)
					then
						t.spush # singleton class
					else
						t.kind = :on_ident
						Token.addMod t.pos, "self."
					end
				when :in
					if t.continuedClause?
						if t.parent.kind == :case
							t.parent.clauseIn t
						elsif t.parent.kind == :in
							if t.parent.argEnd
								t.parent.clauseIn t
							else
								# right assignment 'in'
							end
						end
					elsif t.parent&.kind == :for && t.cur.idtStack.last == t.parent
						t.parent.setIn t
					else
						if t.isSentenceHead?
							if defined?(FreeCase) && t.trySetUnderCase
								t.kind = :free_in
								t.spush
							else
								raise Error.new("orphan in")
							end
						else
							# right assignment 'in'
						end
					end
				when :when
					if t.continuedClause?
						t.parent.clauseWhen t
					else
						if defined?(FreeCase) && t.trySetUnderCase
							t.kind = :free_when
							t.spush
						else
							raise Error.new("orphan when")
						end
					end
				when :rescue
					if t.continuedClause?
						t.parent.clauseRescue t
					else #independent rescue
						if defined?(IndependentRescue)
							t.spush
						else
							raise Error.new("found orphan 'rescue'")
						end
					end
				when :ensure
					if t.continuedClause?
						t.parent.clauseEnsure t
					else #independent ensure
						if defined?(IndependentEnsure)
							t.spush
						else
							raise Error.new("found orphan 'ensure'")
						end
					end
				when :end
					if t.continuedClause?
						Token.addMod t.range, t.parent.wrapped.orgEntity.closeBeginner(t)
						t.spop
					else
						raise Error.new("found extra end")
					end
					############ remove below #############
					case t.parent.kind
					when :case, :free_case
						finalizeCase(t.parent, t)
					when :ensure
						finalizeFreeEnsure.(t.parent)
					when :rescue
						finalizeFreeRescue.(t.parent)
					else
						if t.parent.isIflessStarter?
							finalizeIfless(t.parent)
						elsif t.continuedClause?
							# protect over pop indentation
							case (lo = t.parent.wrapped.orgEntity).kind # without iterator method information 'cause may start post test while or until
							when :do ########### do"
								if c = lo.parent.iteratorCand
									if lo.iteratorMethod = c.trySetupIterator :preset, lo, t
										lo.parent.iteratorCand = nil
									end
								else
									case lop = lo.prev
									when :on_rbracket
										lo.iteratorMethod = lop.beginner
									when :on_rparen
										tt = lop.beginner.prev
										lo.iteratorMethod = tt.trySetupIterator :back, lo, t
									end
								end
								if !lo.iteratorMethod
									raise Error.new("cannot find iterator method identifier for 'do'")
								end
							when :until, :while
								lo.trySetupIterator :forward, lo, t
							when :then, :else, :elsif # ifless
								finalizeIfless t
							end
							t.spop
						else
							raise Error.new("found extra end")
						end
					end
				when :while, :until
					if t.parent.kind == :do && !t.parent.iteratorCand && defined?(PostTestDo)
						t.parent.setPostTest t
					else
						t.spush
					end
				end
				#check label
				if t.kind == :on_label && 
					if (t.str == "do:") || 
						(["while:", "until:"].include?(t.str) && ([:on_nl, :on_semicolon].include?(t.dprev.prev.kind) || t.dprev.prev.continues?))
					
						if t.maybeIteratorLabel? true
							# NG do:label [,):};\n]
							# NG do:label ^ foo # cannot be interpreted as unary operator
							# OK do:label ! foo # unary operator
							# OK do:label + 1   # interpreted as unary operator
							# do not need check :post_test_do because 'do ... while:label cond' is not allowed
							t.setupIteratorLabel
							t.spush
						end
					end
				end
				allTokens.push t
			end
		rescue Restart
			allTokens.clear
			@restarted = true
			retry
		rescue StopIteration
		end
		if mode
			if mode.to_s =~ /_quote$/
				raise Error.new("cannot find closing end of quotation")
			else
				raise Error.new("cannot find closing end of brace")
			end
		end
	end
	attr_reader :pos, :kind, :str, :stat, :restarted
	def self.translate opts, expr, f, lno
		new expr, opts, f, lno
	end
end










