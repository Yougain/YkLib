#!/usr/bin/env ruby


require 'Yk/tty_char'


class TZWhen
	def self.& obj
		new obj
	end
	def initialize obj
		@args = []
		if obj.is_a? Symbol
			@mname = obj
		else
			@obj = obj
		end
	end
	def & ag
		if !@obj
			@obj = ag
		else
			(@args ||= []).push ag
		end
		return self
	end
	def === carg
		if !@obj
			carg.method(@mname).call *@args
		elsif @mname
			args = []
			@args.each do |e|
				if e == :_1
					args.push carg
				else
					args.push e
				end
			end
			@obj.method(@mname).call(*args)
		else
			raise Exception("unbound method")
		end
	end
end


class String
	class SGRStat
		Reset = "\x1b[0m\x1b[39m\x1b[49m"
		def << code
			while code =~ /((((3|4)8);(5;\d+|2;\d+;\d+;\d+))|(\d+))($|;)/
				tcCmd, cmd, code = $2, $6 ? $6.to_i : $3.to_i, $'
				case cmd
				when 0
					@bold = nil
					@thin = nil
					@italic = nil
					@underline = nil
					@blink = nil
					@reverse = nil
					@hidden = nil
					@strike = nil
					@fgColor = nil
					@bgColor = nil
				when 1
					@bold = true
				when 2
					@thin = true
				when 3
					@italic = true
				when 4
					@underline = true
				when 5
					@blink = :on
				when 6
					@blink = :quick
				when 7
					@reverse = true
				when 8
					@hidden = true
				when 9
					@strike = true
				when 30 .. 37
					@fgColor = code % 30
				when 38
					@fgColor = tCmd
				when 39
					@fgColor = -1
				when 40 .. 47
					@bgColor = code % 30
				when 48
					@bgColor = tCmd
				when 49
					@bgColor = -1
				when 90 .. 97
					@fgColor = code % 90 + 10
				when 100 .. 107
					@bgColor = code % 100 + 10
				end
			end
		end
		def restart
			cmds = []
			@bold && cmds.push(1)
			@thin && cmds.push(2)
			@italic && cmds.push(3)
			@underline && cmds.push(4)
			case @blink
			when :on
				cmds.push(5)
			when :quick
				cmds.push(6)
			end
			@reverse && cmds.push(7)
			@hidden && cmds.push(8)
			@strike && cmds.push(9)
			case @fgColor
			when 0..7
				cmds.push(@fgColor + 30)
			when 10..17
				cmds.push(@fgColor + 80)
			when -1
				cmds.push(39)
			when nil
			else
				cmds.push(38, *@fgColor.split(/;/))
			end
			case @bgColor
			when 0..7
				cmds.push(@bgColor + 40)
			when 10..17
				cmds.push(@bgColor + 90)
			when -1
				cmds.push(49)
			when nil
			else
				cmds.push(48, *@bgColor.split(/;/))
			end
			"\x1b[#{cmds.map{|e| e.to_s}.join(';')}m"
		end
	end
	def String.tty_char_width c
		->{
			if c.size > 1
				if c[0] == "\x1b"
					return 0 # escape sequence
				else
					raise Exception("is not one character")
				end
			end
			a = TTYChar::Alt[c]
			if a
				a.size
			else 
				TTYChar::Width[c]
			end
		}[] || '\u{' + c.ord.to_s(16) + '}'.size
	end
	def tty_alt
		->{
			a = TTYChar::Alt[self]
			if a
				a
			elsif TTYChar::Width[self]
				self
			end
		}[] || '\u{' + ord.to_s(16) + '}'
	end
	class TTYPos
		def initialize buff, locOrTopTTYPos
		end
		def slice! #entityの場合、後続のアクサンを削除
		end
		def set pos
		end
		def < arg
		end
		def <= arg
		end
		def > arg
		end
		def >= arg
		end
		def +
		end
		def -
		end
		def move_tty_size
		end
		def set_at_entity pos
		end
		def tty_location
		end
	end
	def is_combining?
		TTYChar::Width[self] == 0
	end
	def is_attribute?
		self =~ /^\x1b\[(\d+(;\d+)*)m$/
	end
	def is_escseq?
		self =~ /\x1b(\[(\d+(;\d+)*|)([^\d;])|[O#()].|.)$/
	end
	def is_combinable?
		if size == 1
			ord = self.ord
			if ord < 0x20 || (0x7f <= ord && ord <= 0x80) || org == 0xad
				return false
			end
			if TTYChar::Width[self] == 1 || TTYChar::Width[self] == 2
				return true
			end
		end
		return false
	end
	def tty_width tabstop = 8
		ret = 0
		escRemoved = self.gsub /\x1b(\[(\d+(;\d+)*|)([^\d;])|[O#()].|.)/, ""
		escRemoved.each_char do |c|
			case c
			when "\t"
				ret = (ret.div tabstop) * tabstop
			else
				ret += TTYChar::Width[c]
			end
		end
		ret
	end
	def tty_len range
		tty_each do |c|
			
		end
	end
	def tty_substr range
		
	end
	def _tty_width
		ret = 0
		escRemoved = self.gsub /\x1b(\[(\d+(;\d+)*|)([^\d;])|[O#()].|.)/, ""
		escRemoved.each do |c|
			ret += TTYChar::Width[c]
		end
		ret
	end
	def tty_slice! w
		i = 0
		each do |c|
			cw = TTYChar::Width[c]
			if w - cw < 0
				break
			end
			i += 1
		end
		slice!(0...i)
	end
	class LetterDivider
		def initialize &bl
			@buff = ""
			@block = bl
			@gs = GStat.new
		end
		def flush
			return if !@char
			lmode = case @char
			when " "
				@forceLetter ? :non_space : :space
			when "\t"
				:tab
			when TZWhen & "`'\"([{「『（｛〔［【‘“《〈‹«" & :include?
				:no_last
			when TZWhen & " 、。，．・：；！？」』）｝〕］】!?%)\]},.:;'\"`’”》〉›»" & :include?
				:no_first
			else
				:non_space
			end
			@block[@buff, @char, lmode, @gs]
			@char = nil
			@forceLetter = false
			true
		end
		def << c
			if c.is_combining?
				if !@char || (!@char.is_combinable? && flush)
					@char = " "
					@buff += " "
				end
				@buff += c
				@forceLetter = true
			elsif c.is_attribute?
				@buff += c
				@gs << c
				@gs = @gs.clone
			elsif !c.is_escseq?
				if @char
					flush
				else
					@char = c
					@buff += c
				end
			end
		end
		def close
			flush if @char
		end
	end
	NSPC = /[^ \t]/
	NFST = /[^ 、。，．・：；！？」』）｝〕］】!?%)\]},.:;'\"`’”》〉›»]/
	NLST = /[^`'"(\[{「『（｛〔［【‘“《〈‹«]/
	def tty_each_word
		ret = ""
		c = nil
		last_char = nil
		last_lmode = nil
		last_gs = nil
		ld = LetterDivider.new do |c, char, lmode, gs|
			case Match::Tuple[last_char, char]
			when [nil, /\w/], [/(\.|\-|\w)/, /\w/], [/\d/, /(\.|\-)/]
				ret += c
			else
				case [last_mode, mode]
				when [:non_space, :no_first], [:no_last, :non_space]
					ret += c
				else
					yield ret, last_lmode, last_gs if ret != ""
					ret.replace c
				end
			end
			last_char = char
			last_gs = gs
			last_lmode = lmode
		end
		while res =~ /\x1b(\[(\d+(;\d+)*|)([^\d;])|[O#()].|.)/
			c, nres = $&, $'
			ld << c
		end
		yield ret, last_lmode, last_gs if ret != ""
	end
	def tty_each_line width, tabstop = 8, &bl
		_tty_line width width, tabstop, &bl
	end
	def tty_line width, tabstop = 8
		_tty_line width width, tabstop
	end
	def _tty_line width, tabstop = 8, &bl #block is needed if print multiline
		ln = ""
		isMultiLine = false
		pos = 0
		tty_each_word do |w, lmode, gs|
			case lmode
			when :tab
				newPos = (pos.div tabstop) * tabstop
				if newPos > width
					ln += w.sub("\t", " " * (width - pos))
					pos = width
				else
					ln += w.sub("\t", " " * (newPos - pos))
					pos = newPos
				end
			when :space
				if isMultiLine && pos == 0
					ln += w.sub(" ", "")
					next
				end
			else
				newPos = pos + w._tty_width
				if newPos > width
					if pos > 0
						ln += " " * (width - pos)
						pos = 0
					else
						sliced = w.tty_slice!(width)
						if sliced != ""
							ln += sliced
						end
					end
					if bl
						bl.call ln + SGRStat::Reset
						isMultiLine = true
					else
						return ln + SGRStat::Reset
					end
					ln.replace gs.restart
					redo
				else
					ln += w
				end
			end
			if pos >= width
				if bl
					bl.call ln + SGRStat::Reset
					isMultiLine = true
				else
					return ln + SGRStat::Reset
				end
				ln.replace gs.restart
				pos = 0
			end
		end
		if bl
			bl.call ln + SGRStat::Reset if ln != ""
		else
			return ln + SGRStat::Reset
		end
	end
	InputConv = {
		"\x1b[A" => :up,
		"\x1b[B" => :down,
		"\x1b[C" => :right,
		"\x1b[D" => :left,
		"\x1b[5~" => :pgaeUp,
		"\x1b[6~" => :pgaeDown,
		"\x1b[H" => :home,
		"\x1b[F" => :end,
		"\x1b[3" => :del,
		"\x7f" => :bs,
		"\r" => :enter,
		"\x1bOR" => :f3,
		"\x1b[1;2R" => :F3,
		"\x1b" => :esc,
		"\u0003" => :INT
	}
	def tty_each
		res = self
		while res =~ /^(\x1b(\[(\d+(;\d+)*|)([^\d;])|[O#()].|.)|.)/
			yield $&
			res = $'
		end
	end
	def tty_each_input
		res = self
		while res =~ /^(\x1b(\[(\d+(;\d+)*|)([^\d;])|[O#()].|.)|.)/
			c = $&
			cv = InputConv[c]
			if !cv && (c.ord < 0x20 || (0x80 <= c.ord && c.ord <= 0x9f))
				cv = c.intern
			end
			yield cv || c
			res = $'
		end
	end
end


if __FILE__ == $0
	require 'Yk/fib'
	require 'Yk/path_aux'
	require 'Yk/debug2'
	Fib.spawn do
		"/proc/#{$$}/fd/0".readlink.open "rw" do |fp|
			fp.set_raw
			buff = ""
			loop do
				c = Fib.read fp, buff
				buff.tty_each_input do |c|
					print c.inspect + "\r\n"
				end
			end
		end
	end
end

