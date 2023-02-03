

class AdhocLiterals
	class Path
		def initialize arg
			@literal = arg
		end
	end
	def self.__path__ arg
		Path.new arg
	end
end


class GrammerExt
	class Indenter
		PATH_HEAD = "AdhocLiterals::__path__("
		BOTH_HEAD = "AdhocLiterals::__reg_path__("
		CSelectInPathRegExpr = '\[(\!|\^|)(\\\-|\.|\~|\w|[A-Z]\-[A-Z]|[a-z]\-[a-z]|[0-9]\-[0-9])*\]'
		CSelectInPathRegExprPrev = Regexp.new(CSelectInPathRegExpr + '$')
		CSelectInPathRegExprCur = Regexp.new('^' + CSelectInPathRegExpr)
		def mayConcatenatePath t
			if t.kind != :on_nl && t.kind != :on_sp && !@expr.anot[t.ipos]
				ett = tt = t.prev_meaningful
				if fap, mode = @expr.anot[tt.ipos]
					modeList.unshift [mode, tt.ipos]
					loop do
						begin
							ftt = tt
							tt = tt.prev_meaningful
						end until fap != (tfap, mode = @expr.anot[tt.ipos])[0]
						if mode
							modeList.unshift [mode, tt.ipos]
						else
							break
						end
						fap = tfap
					end
					if modeList.size > 1
						modeList.each_cons 2 do |f, n|
							case [f[0][0], n[0][0]]
							when [:sl_beg, :sl_beg],
								[:sl_beg, :sl_both],
								[:sl_middle, :sl_beg],
								[:sl_middle, :sl_both],
								[:sl_end, :sl_end],
								[:sl_end, :sl_middle],
								[:sl_both, :sl_end],
								[:sl_both, :sl_middle],
								[:sl_url, :sl_beg],
								[:sl_url, :sl_both]
							else
								raise Error.new("cannot concatenate path")
							end
						end
					end
					toConcatenate = @expr[ftt.ipos...ett.ipos + ett.str.size]
					head = if defined?(AdhocLiterals::Url) && @expr[ftt.iops] =~ /^[a-zA-Z][a-zA-Z0-9\.+\-]*:/
						URL_HEAD
					elsif defined?(AdhocLiterals::Path)
						modeList[0][1] == :both ? BOTH_HEAD : PATH_HEAD
					end
					if head
						@expr[ftt.ipos...ett.ipos + ett.str.size] = head + toConcatenate + ")"
						@expr.clear_anot
						raise Restart.new
					end
				end
			end
		end
		def pathRestart st, ed, pstack, mode
			subst = ""
			inDQ = false
			dqStart = nil
			if st < pstack[0]
				if !["'", '"'].include? @expr[st]
					subst += '"'
					dqStart = st
					inDQ = true
				end
			end
			pstack.each_index do |idx|
				i, j = pstack[idx], pstack[idx + 1]
				if inDQ
					if j
						if i + 1 == j
							next
						elsif ["'", '"'].include? @expr[i + 1]
							subst += @expr[dqStart .. i] + '"'
							inDQ = false
						end
					end
				else
					subst += '"'
					dqStart = i
					inDQ = true
				end
			end
			# inDQ should be true
			if ed - 1 > pstack[-1]
				if ["'", '"'].include? @expr[ed - 1]
					subst += @expr[dqStart .. pstack[-1]] + '"' + @expr[pstack[-1] + 1 ... ed]
				else
					subst += @expr[dqStart ... ed] + '"'
				end
			else
				subst += '"'
			end
			emode = case [@expr[st] == "/", @expr[ed] == "/"]
			when [true, true]
				:sl_both
			when [true, false]
				:sl_beg
			when [false, true]
				:sl_end
			when [false, false]
				:sl_middle
			end
			@expr.ssubst st...ed, subst, [mode, emode]
			raise Restart.new
		end
		# /"can use backslash escape"		:path
		# /cannot_use_backslash_escape		:path
		# /using\ backslash\ /				:regexp
		# /path[)}\]]						:path and closing ')', '}', ']'
		# /path,(\s|$)						:path '/path' and comma operator
		# /path\s							:path '/path'
		# /foo/i							:both functional object '/foo/i', without space and backslash until closing '/'
		# /foo/.to_s						:path '/foo/.to_s'
		# /foo/ .to_s						:both functional object '/foo/' calling method '.to_s'
		# / a		 	:devide operator
		# /ab[)\]}] 	:path, '/ab' and parenthesis/bracket/brace closing
		# /ab,(\s|$)  	:path, '/ab' and comma operator
		# /ab,c			:path, '/ab,c'
		# /"ab c" 	 	:path
		# /"ab c"aaa	:error
		# /abc"aa		:error
		# /abc"aa/		:regexp
		# /abc"aa /		:error: path '/abc"aa', '/'
		# /"abc / regexp
		# /"abc/" error, path segment cannot contain '/'
		# /"abc\/" error, path segment cannot contain '/'
		# /\"abc d/ regexp
		# /* c comment start
		# 
		def checkPath st, origin = nil, pstack = []
			firstSlash = @expr[st] == "/"
			bstack = []
			i = st
			i += 1 if @expr[i] == "}" #embeded expression closing
			k = nil
			res = nil
			mode = origin && st != origin ? :path : nil
			while o = @expr[i]
				case o
				when "/"
					pstack.push i
					if pstack.size == 3
						mode = :path
					end
					rp = i
					while ["'", '"'].include? @expr[i + 1]
						i = getStringEndExceptSlash(i + 1)
						if !i
							raise Error.new("cannot find string end, #{@expr[i + 1]}")
						else
							j = i
							while @expr[i + 1] == "/"
								i += 1
								pstack.push i
							end
						end
					end
					if rp != i
						mode = :path
						if @expr[i] != "/"
							break # /"foo"[^\/]
						end
					#else continue after "/"
					end
				when ",", ";"
					if @expr[i, 2] =~ /^.(\s|$)/
						break
					end
				when '"', "'", "`"
					break
				when ")", "]", "}" #orphan
					break
				when "[", "{", "("
					break if !firstSlash
					if !(k = getClosing(i))
						raise Error.new("cannot find closing #{@expr[i]}")
					end
				when "#" #embeded expression do not allow first ".", "/", "?", "*", "{}", "[]", otherwise use #wpd{...}, w:wild([],{}.?,*), p:period(.), d:directory(/)
					k = checkExtendedEmbExpr(i, :path)
				when "\\"
					if mode == :path || pstack.size >= 2
						raise Error.new("path expression without double quotation cannot contain bare backslash, '\\'")
					else
						mode = :regexp
						break
					end
				when /\s/
					break
				else
					if o < 0x20
						raise Error.new("cannot use control character, chr(0x0x#{o.t_s.sprintf('%02x')})")
					end
				end
				if !k
					i += 1
				else
					i = k + 1
					k = nil
				end
			end
			if !mode && pstack.size == 2
				ropts = "uesnmxi"
				j = 1
				while (c = @expr[pstack[1] + j]) && (roi = ropts.index(c))
					ropts.slice!(roi)
					++j
				end
				if j != 1 && @expr[pstack[1] + j - 1, 2] =~ /.\b/
					mode = :both
				else
					mode = :path
				end
			end
			if pstack.size != 0
				if firstSlash
					if !origin || origin == st
						pathRestart @expr, st, i, pstack, mode
					else
						pathRestart @expr, origin, i, pstack, mode
					end
				else
					yield i, pstack
				end
			end
		end
		def checkPrevIsPath tenum, st = nil, ed = nil, pstack = nil
			if tenum
				t = token = tenum.peek
				last = nil
				while t.prev&.kind == :on_tstring_end && ['"', "'"].include?(t.prev.beginner.str[0])
					t = t.beginner
				end
				if t != token
					checkPath token.ipos, t.ipos # no return raise Restart
				end
				i = token.ipos
			else
				i = st
			end
			k = nil
			while o = @expr[i]
				case o
				when "[", "{", "("
					break
				when "]", "}", ")"
					#if !(k = getOpening(@expr, i))
						break
					#end
				when "\\", '"', "'", '`'
					break
				when 0x20
					if @expr[i - 1] == "\\"
						i -= 1
					else
						break
					end
				else
					if o < 0x20
						break
					end
				end
				if k
					i = k - 1
					k = nil
				else
					i -= 1
				end
			end
			if tenum
				checkPath token.ipos, i + 1
			else
				pathRestart i + 1, ed, pstack, :path
			end
		end

	end
end