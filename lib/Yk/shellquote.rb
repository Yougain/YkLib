class String
	def shellSQuote (mode = true)
		if self[-1] == ?\\
			self =~ /\\+$/
			post = '"' + $& + $& + '"'
			tmp = $'
		else
			post = ""
			tmp = self
		end
		tmp = tmp.gsub('\'', '\'"\'"\'')
		if mode
			tmp = "'" + tmp + "'"
		end
		tmp + post
	end
	def shellSQuote! (mode = true)
		self.replace(shellSQuote(mode))
	end
	def condSQuote (mode = true)
		if self =~ /\s/ || self =~ /\'/
			tmp = strip
			if tmp.size >= 2 && ((tmp[0] == ?\' && tmp[-1] == ?\') || (tmp[0] == ?\" && tmp[-1] == ?\"))
				tmp
			else
				self.shellSQuote
			end
		else
			self
		end
	end
	def condSQuote! (mode = true)
		self.replace(condSQuote(mode))
	end
	def shellDQuote (mode = true)
		tmp = self.gsub(?\\.chr, "\\\\")
		tmp = self.gsub("\"", "\""'"'"\"")
		if mode
			tmp = "\"" + tmp + "\""
		end
		tmp
	end
	def shellDQuote! (mode = true)
 		self.replace(shellDQuote(mode))
	end
	def condDQuote (mode = true)
		if self =~ /\s/ || self =~ /\"/
			tmp = strip
			if tmp.size >= 2 && ((tmp[0] == ?\' && tmp[-1] == ?\') || (tmp[0] == ?\" && tmp[-1] == ?\"))
				tmp
			else
				self.shellDQuote
			end
		else
			self
		end
	end
	def condDQuote! (mode = true)
		self.replate(condDQuote(mode))
	end
end


class Array
	def shellSQuote
		arr = []
		each do |e|
			arr.push e.shellSQuote
		end
		arr.join(" ")
	end
	def condSQuote
		arr = []
		each do |e|
			arr.push e.condSQuote
		end
		arr.join(" ")
	end
	def shellDQuote
        arr = []
        each do |e|
            arr.push e.shellDQuote
        end
        arr.join(" ")
	end
	def condDQuote
        arr = []
        each do |e|
            arr.push e.condDQuote
        end
        arr.join(" ")
	end
end



require 'Yk/generator__.rb'
require 'shellwords'


class String
	def dequote (env = nil)
		ret = ""
		g = nil
		procEnv = Proc.new do
			if env && g.current == ?$
				if !g.next?
					ret += "$"
				else
					g.inc
					vName = g.current.chr
					if g.current.chr =~ /^[A-Za-z_]$/
						while g.next? && g.next.chr =~ /^\w$/
							g.inc
							vName += g.current.chr
						end
						if env[vName]
							ret += env[vName]
						end
					elsif g.current.chr =~ /^\s$/
						ret += "$#{g.current.chr}"
					else
						if env[vName]
							ret += env[vName]
						end
					end
				end
				true
			else
				false
			end
		end
		self.each__ :each_byte do |g|
			case g.current.chr
			when '"'
				while true
					g.inc
					if g.current == ?\"
						break
					else
						if g.current == ?\\
							g.inc
							case g.current
							when ?0
								ret += "\x00"
							when ?n
								ret += "\n"
							when ?t
								ret += "\t"
							when ?r
								ret += "\r"
							when ?a
								ret += "\a"
							when ?x
								tmp = ""
								g.inc
								tmp += g.current.chr
								g.inc
								tmp += g.current.chr
								ret += tmp.to_x.chr
							when ?\\
								ret += "\\"
							when ?\"
								ret += '"'
							when ?\'
								ret += "'"
							end
						elsif !procEnv.call
							ret += g.current.chr
						end
					end
				end
			when "'"
				while true
					g.inc
					if g.current == ?\'
						break
					else
						if g.current == ?\\ && g.next? && g.next == ?\'
							g.inc
						end
						ret += g.current.chr
					end
				end
			else
				if !procEnv.call
					ret += g.current.chr
				end
			end
		end
		ret
	end
	def shell_split (*envOrComtOrLim)
		if envOrComtOrLim.size == 0
			return Shellwords.shellwords(self)	
		end
		s = self
		env = nil
		comt = "#"
		spPos = []
		arr = []
		lim = nil
		com = ""
		envOrComtOrLim.each do |e|
			if e.is_a?(Hash) || e == ENV
				env = e
			elsif e.is_a? String
				comt = e
			elsif e.is_a? Integer
				lim = e
			end
		end
		s.each__ :each_byte do |g|
			case g.current.chr
			when '"'
				begin
					g.current == ?\\ && g.inc
					g.inc
				end while g.current != ?\"
			when "'"
				begin
					g.current == ?\\ && g.next == ?\' && g.inc
					g.inc
				end while g.current != ?\'
			when /^\s$/
				start = g.index
				while g.next? && g.next.chr =~ /^\s$/
					g.inc
				end
				stop = g.index
				spPos.push start..stop
			when comt
				spPos.push(tmp = g.index .. s.size - 1)
				com = s[tmp]
				break
			end
		end
		prevLast1 = 0
		spPos.each do |sr|
			if sr.first != 0
				if prevLast1 <= sr.first - 1
					arr.push s[prevLast1 .. sr.first - 1]
					if arr.size == lim
						arr[-1] += s[sr.first ... s.size - com.size - 1]
						arr[-1].rstrip!
						prevLast1 = s.size
						break
					end
				end
			end
			prevLast1 = sr.last + 1
		end
		if prevLast1 < s.size
			arr.push s[prevLast1 .. s.size - 1]
		end
		arr.map!{ |e| e.dequote(env) }
		def arr.com= (arg)
			@com = arg
		end
		def arr.com
			@com
		end
		arr.com = com
		arr
	end
end


class Array
	def shell_join (*splOrQuots)
		qMode = :dQuot
		spl = " "
		splOrQuots.each do |e|
			case e
			when ?\', "'"
				qMode = :sQuot
			when ?\", '"'
				qMode = :dQuot
			else
				if e.is_a? Integer
					spl = e.chr
				else
					spl = e
				end
			end
		end
		case qMode
		when :sQuot
			toJoin = map{ |e| e.condSQuote }
		when :dQuot
			toJoin = map{ |e| e.condDQuote }
		end
		if self.respond_to?(:com) && com != nil
			toJoin += [com]
		end
		toJoin.join(spl)
	end
end


