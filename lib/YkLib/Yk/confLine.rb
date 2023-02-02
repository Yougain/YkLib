
	class ConfLine < String
		class Error < Exception
		end
		@@definitions = Hash.new { |h, k| h[k] = Hash.new }
		def resolvIt (arg, parent)
			ret = []
			mode = true
			wd = ""
			addByte = Proc.new do |c|
				wd += c.chr
			end
			checkWord = Proc.new do
				if mode
					while wd =~ (/\$(\{|)([A-Za-z_]\w*)(\1)/)
						pre = $`
						if pre && pre != ""
							ret += pre.split_chunk(/[\,\s]+/)
						end
						post = $'
						val = $2
						if tmp = resolvDef(val)
							if tmp =~ /\%\d+/
								args = getArguments(post)
								if args
									tmp = tmp.setArgs(args)
								end
							end
						end
						ret.push tmp
						wd = post
					end
				end
				ret += wd.split_chunk(/[\,\s]+/)
				wd = ""
			end
			catch :brkr do
				curPos = 0
				g = Object.new
				g.__defun__ :+@ do
					arg[curPos]
				end
				g.__defun__ :inc do
					curPos += 1
					if curPos == arg.size
						throw :brkr
					end
				end
				g.__defun__ :next do
					arg[curPos + 1]
				end
				def g.loop (&bl)
					while true
						yield
						inc
					end
				end
				g.loop do
					case +g
					when ?\"
						mode = true
						g.inc
						begin
							if +g == ?\\
								g.inc
								case +g
								when ?\\
									addByte.call ?\\
								when ?n
									addByte.call ?\n
								when ?t
									addByte.call ?\t
								else
									addByte.call +g
								end
								next
							end
							addByte.call +g
							g.inc
						end while +g != ?\"
						checkWord.call
					when ?\'
						mode = false
						g.inc
						begin
							if +g == ?\\
								g.inc
								case +g
								when ?'
									addByte.call "'"
								else
									addByte.call ?\\
									addByte.call +g
								end
								next
							end
							addByte.call +g
							g.inc
						end while +g != ?\'
						checkWord.call
					else
						mode = true
						begin
							addByte.call +g
							g.inc
						end while g.next != ?\" && g.next != ?\'
						checkWord.call
					end
				end
			end
			checkWord.call
			ConfLine.new(ret, parent)
		end
		def getArguments (str, parent)
			ret = []
			i = 0
			cnt1 = 0
			cnt2 = 0
			cnt3 = 0
			pth = nil
			if str[0] != ?(
				return nil
			end
			while i < str.size
				case pth
				when nil
					case str[i]
					when ?(
						cnt1 += 1
						if cnt1 == 1
							start = i + 1
						end
					when ?)
						cnt1 -= 1
						if cnt1 == 0
							ret.push resolvIt(str[start .. i - 1].strip, parent)
							start = nil
							str[0 .. i] = ""
							break
						end
					when ?{
						cnt2 += 1
					when ?}
						cnt2 -= 1
					when ?[
						cnt3 += 1
					when ?]
						cnt3 -= 1
					when ?"
						pth = ?\"
					when ?'
						pth = ?\'
					when ?,
						if cnt1 == 1 && cnt2 == 0 && cnt3 == 0
							ret.push resolvIt(str[start .. i - 1].strip, parent)
							start = i + 1
						end
						start = i + 1
					end
				when "\\\'"
					pth = ?\'
				when "\\\""
					pth = ?\"
				when ?\'
					case str[i]
					when ?\'
						pth = nil
					when ?\\
						pth = "\\\'"
					end
				when ?\"
					case str[i]
					when ?\"
						pth = nil
					when ?\\
						pth = "\\\""
					end
				end
				i += 1
			end
			return ret
		end
		def getChunk (i)
			self[@chunks[i]]
		end
		def chunks (arg = nil)
			if arg.is_a? Range
				res = ""
				(tmp = @chunks[arg]).each_index do |i|
					e = tmp[i]
					if i != 0 && res.respond_to?(:prefix)
						res += e.prefix
					end
					res += e
					if i != tmp.size - 1 && res.respond_to?(:postfix)
						res += e.postfix
					end
				end
				res
			elsif arg != nil
				@chunks[arg]
			else
				@chunks
			end
		end
		def resolvDef (arg)
			@definitionFiles.each do |f|
				if @@definitions.key?(f)
					if tmp = @@definitions[f][arg]
						return tmp
					end
				end
			end
			nil
		end
		def registerDefFile (defFile)
			if defFile && defFile.readable_file? && !@@definitions.key?(defFile)
				defFile.read_each_line do |ln2|
					ConfLine.new(ln2, defFile, nil)
				end
				if @@definitions.key? defFile
					@definitionFiles.push defFile
				end
			end
		end
		attr :definitionFiles
		attr :scope
		def setArgs (args, parent)
			arr = []
			chunks.each do |e|
				if e =~ /\%\d+/
#					if e.respond_to? :chunks
#						arr.push e.setArgs(args, parent)
#					else
						while e =~ /\%(\d+)/
							pre, hit, id, post = $`, $&, $1.to_i - 1, $'
							if pre && pre != ""
								arr += pre.split_chunk(/[\,\s]+/)
							end
							if tmp = args[id]
								arr.push tmp
							else
								arr.push hit
							end
							e = post
						end
						if e && e != ""
							arr.push e
						end
#					end
				else
					arr.push e
				end
			end
			ConfLine.new(arr.join.split_chunk(/[\,\s]+/), parent)
		end
		def initialize (ln, sc, incFiles = nil, noDef = false)
			super()
			if !ln.is_a? Array
				@scope = sc
				@definitionFiles = [@scope]
				if incFiles.is_a? Array
					incFiles.each do |e|
						registerDefFile e
					end
				else
					registerDefFile e
				end
				@definitionFiles.push nil
				tmp = ""
				ln.each_line do |l|
					l.sub!(/\#.*$/, "")
					l.strip!
					tmp += l.ln!
				end
				if !noDef && ln =~ /([A-Za-z_]\w*)\s*\=\s*(.*)/m
					m1, m2 = $1, $2.strip
					@@definitions[@scope][m1] = ConfLine.new(m2, @scope, incFiles, true)
					replace("")
				else
					res = ln
					arr = []
					while res =~ (/\$(\{|)([A-Za-z_]\w*)(\1)/)
						pre = $`
						post = $'
						val = $2
						if pre && pre != ""
							arr.push *pre.split_chunk(/[\,\s]+/)
						end
						if tmp = resolvDef(val)
							if tmp =~ /\%\d+/
								args = getArguments(post, self)
								tmp = tmp.setArgs(args, self)
							end
							arr.push tmp
						else
							arr.push "$" + val
						end
						res = post
					end
					arr.push *res.split_chunk(/[\,\s]+/)
					@chunks = arr
					replace(arr.join)
				end
				if block_given? && self != ""
					yield self
				end
			else
				arr, parent = ln, sc
				@chunks = arr
				@scope = parent.scope
				@definitionFiles = parent.definitionFiles
				replace(arr.join)
			end
		end
	end


	module ConfFile
		module_function
		def getSection_l (f, sec, scope = nil, preLoad = [], preParser = nil, &bl)
			getSection_(true, f, sec, scope, preLoad, preParser, &bl)
		end
		def getSection (f, sec, scope = nil, preLoad = [], preParser = nil, &bl)
			getSection_(nil, f, sec, scope, preLoad, preParser, &bl)
		end
		def getSection_ (lck, f, sec, scope = nil, preLoad = [], preParser = nil)
#			if !scope
#				scope = f
#			end
			@cList ||= Hash.new
			@cList[f] ||= splitSection_(lck, f)
			res = nil
			notFound = Proc.new do
				if ((tmp = @cList[f].keys).size == 1 && tmp[0] == nil)
					@cList[f][nil]
				elsif tmp.size == 0
					""
				else
					nil
				end
			end
			if sec.is_a? Regexp
				ret = nil
				@cList[f].keys.select{ |e| e =~ sec}.each do |k|
					if !ret
						ret = ""
					end
					ret += @cList[f][k]
				end
				if !ret
					notFound.call
				else
					res = ret
				end
			else
				if !@cList[f].key?(sec)
					notFound.call
				else
					res = @cList[f][sec]
				end
			end
			i = 0
			if res
				res = res.lines
				pobj = preParser.new if preParser
				while i < res.size
					ln = res[i]
					while ln[-2] == ?\\
						ln = ln.chomp.chop.ln
						if i == res.size - 1
							break
						end
						i += 1
						ln += res[i]
					end
					if pobj
						pobj.call ln do |ln2|
							cl = ConfLine.new(ln2, scope, preLoad)
							if ln2.respond_to? :extra_properties
								ln2.extra_properties.each do |l|
									cl.__defun__ l, ln2.method(l).call
								end
							end
							yield cl
						end
					else
						yield ConfLine.new(ln, scope, preLoad)
					end
					i += 1
				end
			end
		end
		def splitSection_ (lck, f)
			secs = Hash.new { |h, k| h[k] = "".clone }
			sec = nil
			if lck
				f.read_each_line_l do |ln|
					if ln =~ /^\s*\[([^\]\#]+)\]/
						sec = $1.strip
						ln = $'
					end
					secs[sec] += ln
				end
			else
				f.read_each_line do |ln|
					if ln =~ /^\s*\[([^\]\#]+)\]/
						sec = $1.strip
						ln = $'
					end
					secs[sec] += ln
				end
			end
			secs
		end
		def splitSection (f)
			splitSection_(nil, f)
		end
		def splitSection_l (f)
			splitSection_(true, f)
		end
	end
	
