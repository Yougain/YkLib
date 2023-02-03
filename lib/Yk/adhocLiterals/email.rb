

class AdhocLiterals
	class Email
		def initialize arg
			@literal = arg
		end
	end
	def self.__email__ arg
		Email.new arg
	end
end


class GrammerExt
	class Indenter
		EMAIL_HEAD = "AdhocLietarls::__email__("
		def checkEmail st
			if st.is_a? Integer # called from :bare
				atPos = st if @expr[st] == "@" 
				i = st
				i += 1 if @expr[i] == "}" #embeded expression closing
				k = nil
				while o = @expr[i]
					if !atPos
						case o
						when "@"
							atPos = i
						when "#" #embeded expression do not allow first ".", "/", "?", "*", "{}", "[]", otherwise use #wpd{...}, w:wild([],{}.?,*), p:period(.), d:directory(/)
							k = checkExtendedEmbExpr(i, :email)
						when /[()<>[\\\]:;@,"]/
							return nil
						else
							if o.ord <= 0x20
								return nil
							end
						end
					else
						case o.ord
						when ?A.ord .. ?Z.ord, ?a.ord .. ?z.ord, ?0.ord .. ?9.ord, ?..ord, ?-.ord
						when "#" #embeded expression do not allow first ".", "/", "?", "*", "{}", "[]", otherwise use #wpd{...}, w:wild([],{}.?,*), p:period(.), d:directory(/)
							k = checkExtendedEmbExpr(i, :email)
						else
							if o.ord < 0x80
								if atPos != i - 1
									yield i - 1
								else
									return nil
								end
							end
						end
					end
					if !k
						i += 1
					else
						i = k + 1
						k = nil
					end
				end
			else # tenum
				tenum = st
				t = token = tenum.peek
				st = token.first
				if t.dprev&.kind == :on_tstring_end && t.dprev.beginner.str == "\""
					org = t.beginner.first
					orgIsQ = true
				else
					i = token.first - 1
					while o = @expr[i]
						case o
						when /[()<>[\\\]:;@,"]/
							break
						else
							if o.ord <= 0x20
								break
							end
						end
						i -= 1
					end
					i += 1
					if expr[i] == "@"
						return nil
					end
					org = i
				end
				i = token.first + 1
				ed = nil
				while o = @expr[i]
					case o.ord
					when ?A.ord .. ?Z.ord, ?a.ord .. ?z.ord, ?0.ord .. ?9.ord, ?..ord, ?-.ord
					when "#" #embeded expression do not allow first ".", "/", "?", "*", "{}", "[]", otherwise use #wpd{...}, w:wild([],{}.?,*), p:period(.), d:directory(/)
						k = checkExtendedEmbExpr(i, :email)
					else
						if o.ord < 0x80
							if atPos != i - 1
								ed = i - 1
								break
							else
								return nil
							end
						end
					end
					if !k
						i += 1
					else
						i = k + 1
						k = nil
					end
				end
				if orgIsQ
					@expr[org .. ed] = EMAIL_HEAD + '"\\' + @expr[org...st - 1] + '\"' + @expr[st .. ed] + ")"
				else
					@expr[org .. ed] = EMAIL_HEAD + @expr[org .. ed] + ")"
				end
				raise Restart.new
			end
		end
	end
end