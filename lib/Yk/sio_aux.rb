require 'Yk/path_aux'
require 'set'

#p > nil


class IO
	BUFF_SZ = 1024 * 1024

	def use_select # use time interrupt for normal file reading
		@_use_select = true
	end
	def dont_use_select
		@_use_select = false
	end
	class << self
		def _open path, mode = "r", **opt
			begin
				fd = sysopen path, self::NONBLOCK
				io = for_fd(fd, **opt)
				yield io
			ensure
				io.close if io
			end
		end

		def _openw path, mode = "w", offset = nil, **opt
			flg = offset ? TRUNC : 0
			begin
				fd = sysopen path, self::WRONLY|self::NONBLOCK|self::CREAT|flg
				io = for_fd(fd, **opt)
				io.seek offset if offset
				yield io
			ensure
				io.close if io
			end
		end
	
		def _src path
			if !path.is_a? IO
				fr = _open path do |io|
					yield io
				end
			else
				yield io
			end
		end
		def _dst path
			if !path.is_a? IO
				fr = _openw path do |io|
					yield io
				end
			else
				yield io
			end
		end

		def binread path, length = nil, offset = 0
			_open path, "br" do |io|
				if _use_select? io
					io.seek offset
					buff = ""
					while !length || buff.bytesize < length
						Fiber.select io, :read
						readBuff = ""
						begin
							io.read_nonblock(length - buff.bytesize, readBuff)
						rescue EOFError
							break
						else
							buff += readBuff
						end
					end
				else
					io.seek offset
					return io._org_read(length)
				end
			end
		end

		def binwrite path, buff, offset = nil
			_openw path, "bw", offset do |io|
				if _use_select? io			
					length = buff.bytesize
					while wsize < length
						Fiber.select io, :write
						readBuff = ""
						wsize += io.write_nonblock(buff.byteslice(wsize, length - wsize))
					end
				else
					io._org_write buff
				end
			end
		end

		def copy_stream src, dst, copy_length = nil, src_offset = nil
			_src path do |fr|
				fr.seek scr_offset if src_offset
				if fr._use_select?
					_dst path do |fw|
						if fw._use_select?
							cpsz = BUFF_SZ
							if copy_length
								if copy_length < cpsz
									cpsz = copy_length
								end
								readBuff = fr._flush_residue
								copied = 0
								while copied < copy_length
									Fiber.select fr, :read
									begin
										csz = [copy_length - copied, cpsz].min
										fr.read_nonblock(csz, readBuff)
										rsz = readBuff.bytesize
										wsz = 0
										while wsz < rsz
											Fiber.select fw, :write
											wsz += fw.write_nonblock(readBuff.byteslice(wsz, rsz - wsz))
										end
									rescue EOFError
										break
									else
										copied += wsz
									end
								end
							else
								loop do
									Fiber.select fr, :read
									begin
										fr.read_nonblock(BUFF_SZ, readBuff)
										rsz = readBuff.bytesize
										wsz = 0
										while wsz < rsz
											Fiber.select fw, :write
											wsz += fw.write_nonblock(readBuff.byteslice(wsz, rsz - wsz))
										end
									rescue EOFError
										break
									end
								end
							end
						else
							cpsz = BUFF_SZ
							if copy_length
								if copy_length < cpsz
									cpsz = copy_length
								end
								readBuff = ""
								copied = 0
								while copied < copy_length
									Fiber.select fr, :read
									begin
										csz = [copy_length - copied, cpsz].min
										fr.read_nonblock(csz, readBuff)
										fw._org_write(readBuff)
										copied += readBuff.bytesize
									rescue EOFError
										break
									end
								end
							else
								loop do
									Fiber.select fr, :read
									begin
										fr.read_nonblock(BUFF_SZ, readBuff)
										fw._org_write(readBuff)
									rescue EOFError
										break
									end
								end
							end
						end
					end
				else
					_dst path do |fw|
						if fw._use_select?
							cpsz = BUFF_SZ
							readBuff = fr._org_read(copy_length)
							rsz = readBuff.bytesize
							wsz = 0
							while wsz < rsz
								Fiber.select fw, :write
								wsz += fw.write_nonblock(readBuff.byteslice(wsz, rsz - wsz))
							end
						else
							cpsz = BUFF_SZ
							readBuff = fr._org_read(copy_length)
							fw._org_write(readBuff)
						end
					end
				end
			end
		end

		alias_method :_org_foreach, :foreach
		def foreach path, rs = $/, chomp: false, **opt, &bl
			body = ->y{
				readBuff = ""
				lstC = rs != "" ? rs : $/ * 2
				ret = true
				_open path, **opt do |io|
					ret = nil
					if io._use_select?
						left = nil
						begin
							loop do
								Fiber.select io, :read
								io.read_nonblock(BUF_SZ, readBuff)
								readBuff = left + readBuff if left
								readBuff.each_line rs do |ln|
									if ln.byteslice(-lstC.bytesize..-1) == lstC
										y.call chomp ? ln.byteslice(0...-lstC.bytesize) : ln
										left = nil
									else
										left = ln
									end
								end
							end
						rescue EOFError
							y.call left if left
						end
					else
						io._org_each_line rs, chomp: chomp do |ln|
							y.call ln
						end
					end
				end
				ret
			}
			if bl
				body.call ->{ bl[_1] }
			else
				return Enumerator.new do |x|
					body.call ->{ x << _1 }
				end
			end
		end


		alias_method :_org_read, :read
		def read path, length = nil, offset = 0, **opt
			_open path, **opt do |io|
				io.seek offset if offset != 0
				if io._use_select?
					res = ""
					readBuff = ""
					begin
						if length
							while res.bytesize < length
								Fiber.select io, :read
								io.read_nonblock(length, readBuff)
								res += readBuff
							end
						else
							loop do
								Fiber.select io, :read
								io.read_nonblock(BUFF_SZ, readBuff)
								res += readBuff
							end
						end
					rescue EOFError
						return res
					end
				else
					return io._org_read length
				end
			end
		end

		alias_method :_org_readlines, :readlines
		def readlines path, *ag, chomp: false, **opts
			_open path, **opt do |io|
				return io.readlines *ag, chomp: chomp
			end
		end

		alias_method :_org_write, :write
		def write path, buff, offset = nil, **opt
			_openw path, offset, **opt do |io|
				if io._use_select?
					wsz = 0
					while wsz < buff.bytesize
						Fiber.select fw, :write
						wsz += fw.write_nonblock(buff.byteslice(wsz, buff.bytesize - wsz))
					end
				else
					io._org_write buff
				end
			end
		end
	end

	#private
	def __fiber__
		@__fiber__
	end
	def __fiber__= f
		@__fiber__ = f
	end
	def _use_select?
		if @_use_select == nil && ![STDERR, STDIN, STDOUT].include?(self)
			begin
				_org_pos
			rescue Errno::ESPIPE
				@_use_select = true
			else
				@_use_select = false
			end
		end
		@_use_select
	end
	
	def _flush_residue
		@_residue or (
			@_residue = nil;
			""
		)
	end
	
	public
	alias_method :_org_operator_put, :<<
	def << buff
		if _use_select?
			Fiber.select self, :write
			if !buff.is_a? String
				buff = buff.to_s
			end
			wsz = 0
			while wsz < buff.bytesize
				Fiber.select self, :write
				wsz += write_nonblock(buff.byteslice(wsz, buff.bytesize - wsz))
			end
			self
		else
			_org_operator_put buff
		end
	end

	alias _org_each_byte each_byte
	def each_byte &bl
		if _use_select?
			body = ->y{
				begin
					readBuff = _flush_residue
					loop do
						readBuff.each_byte do |ch|
							y.call ch
						end
						Fiber.select self, :read
						read_nonblock(BUF_SZ, readBuff)
					end
				rescue EOFError
				end
			}
			if bl
				body.call ->{ bl[_1] }
			else
				return Enumerator.new do |x|
					body.call ->{ x << _1 }
				end
			end
		else
			_org_each_byte &bl
		end
	end

	alias _org_each_char each_char
	def each_char &bl
		if _use_select?
			body = ->y{
				begin
					readBuff = _flush_residue
					left = nil
					resFirst = readBuff.bytesize == 0
					loop do
						if resFirst
							loop do
								Fiber.select self, :read
								read_nonblock(BUF_SZ, readBuff)
								next if readBuff.size == 0
								readBuff = left + readBuff if left
								resFirst = false
								break
							end
						end
						i = 0
						sz = readBuff.bytesize
						lastChars = []
						readBuff.each_char do |c|
							if sz - i < 4
								lastChars.push [c != c.scrub, c]
							else
								y.call c
							end
							i += c.bytesize
						end
						left = ""
						i = j = 0
						norm = false
						lastChars.reverse_each do |e|
							j += e[1].bytesize
							if !norm && e[0]
								i += e[1].bytesize
							else
								norm = true
							end
						end
						if i == 0
							left = nil
							readBuff.byteslice(-j...-1).each_char do |c|
								y.call c
							end
						else
							left = readBuff.byteslice(-i..-1)
							readBuff.byteslice(-j...-i).each_char do |c|
								y.call c
							end
						end
					end
				rescue EOFError
					left.each_char do |c|
						y.call c
					end
				end
			}
			if bl
				body.call ->{ bl[_1] }
			else
				return Enumerator.new do |x|
					body.call ->{ x << _1 }
				end
			end
		else
			_org_each_char &bl
		end
	end

	alias _org_each_codepoint each_codepoint
	def each_codepoint &bl
		if _use_select?
			body = ->y{
				each_char do |c|
					y.call c.codepoints[0]
				end
			}
			if bl
				body.call ->{ bl[_1] }
			else
				return Enumerator.new do |x|
					body.call ->{ x << _1 }
				end
			end
		else
			_org_each_codepoint &bl
		end
	end

	alias _org_each each
	alias _org_each_line each_line
 	def each_line rs = $/, chomp: false, &bl
 		if _use_select?
			body = ->y{
				readBuff = _flush_residue
				lstC = rs != "" ? rs : $/ * 2
				rsz = BUF_SZ
				left = nil
				resFirst = readBuff.bytesize > 0
				begin
					loop do
						if resFirst
							Fiber.select self, :read
							read_nonblock(rsz, readBuff)
							readBuff = left + readBuff if left
							resFirst = false
						end
						readBuff.each_line rs do |ln|
							if ln.byteslice(-lstC.bytesize..-1) == lstC
								y.call chomp ? ln.byteslice(0...-lstC.bytesize) : ln
								left = nil
							else
								left = ln
							end
						end
					end
				rescue EOFError
					y.call left if left
				end
			}
			if bl
				body.call ->{ bl[_1] }
			else
				return Enumerator.new do |x|
					body.call ->{ x << _1 }
				end
			end
		else
			_org_each_line rs, chomp: chomp, &bl
		end
 	end
 	alias each each_line
 	
 	alias _org_getbyte getbyte
 	def getbyte
 		if _use_select?
	 		if @_residue
	 			case @_residue.bytesize
	 			when 0
	 				@_residue = nil
	 			when 1
	 				ret = @_residue.ord
	 				@_residue = nil
	 				return ret
	 			else
	 				ret = @_residue.byteslice(0..0).ord
	 				@_residue = @_residue.byteslice(1..-1)
	 				return ret
	 			end
	 		end
			begin
		 		loop do
					Fiber.select self, :read
					rb = ""
		 			read_nonblock(1, rb)
		 			if rb.bytesize == 1
		 				return rb.ord
		 			end
		 		end
			rescue EOFError
				return nil
			end
	 	else
	 		_org_getbyte
	 	end
 	end
 	
 	alias _org_getc getc
 	def getc
 		begin
 			readchar
		rescue EOFError
			return nil
		end
 	end
 	
 	alias _org_gets gets
	def gets *ag, chomp: false, **opts
		begin
			readline *ag, chomp: chomp, **opts
		rescue EOFError
			nil
		end
	end

	alias _org_read read
 	def read length = nil, outbuf = ""
 		if _use_select?
			outbuf.replace _flush_residue
			readBuff = ""
			begin
				if length
					while res.bytesize < length
						Fiber.select self, :read
						read_nonblock(length - res.bytesize, readBuff)
						res += readBuff
					end
					if (ls = res.bytesize - length) > 0
						@_residue = res.byteslice(-ls .. -1)
					end
				else
					loop do
						Fiber.select self, :read
						read_nonblock(BUFF_SZ, readBuff)
						res += readBuff
					end
				end
			rescue EOFError
			end
			return res
 		else
 			_org_read length, outbuf
 		end
 	end
 	
 	alias _org_readbyte readbyte
 	def readbyte
 		if _use_select?
	 		if @_residue
	 			if @_residue.bytesize > 0
	 				ret = @_residue.byteslice(1).ord
	 				@_residue = @_residue.byteslice(2..-1)
	 				if @_residue.bytesize == 0
	 					@_residue = nil
	 				end
	 				return ret
	 			else
	 				@_residue = nil
	 			end
	 		end
	 		readBuff = ""
	 		loop do
				Fiber.select self, :read
				read_nonblock(1, readBuff)
				if readBuff.size > 0
					return readBuff[0].ord
				end
			end
 		else
 			_org_readbyte
 		end
 	end
 	
 	alias _org_readchar readchar
 	def readchar
 		if _use_select?
 			buff = _flush_residue
	 		(1..).each do |i|
	 			if i > buff.bytesize
			 		loop do
			 			readBuff = ""
						Fiber.select self, :read
						read_nonblock(1, readBuff)
						if readBuff.size > 0
							buff += readBuff
							break
						end
					end
	 			end
	 			c = buff.byteslice(0, i)
	 			if c == (cscr = c.scrub) # normal char
	 				@_residue = buff.byteslice(i..-1)
	 				return c
	 			elsif c.byteslice(-1..-1) == cscr.byteslice(-1..-1) # abnormal char before normal char
	 				@_residue = buff.byteslice(2..-1)
	 				return buff.byteslice(1) # flush abnormal char, first
	 			end
	 		end
 		else
 			_org_readchar
 		end
 	end

	alias _org_readline readline
	def readline *ag, chomp: false, **opts
 		if _use_select?
			limit = ag[0]._?{_1.is_a?(Integer)} || ag[1]._?{_1.is_a?(Integer)}
			rs = ag[0]._?{_1.is_a?(String)} || ag[1]._?{_1.is_a?(String)} || $/
			lstC = rs != "" ? rs : $/ * 2
			res = []
			rsz = limit ? [BUF_SZ, limit].min : BUF_SZ
			readBuff = _flush_residue
			left = nil
			begin
				getln = ->{
					readBuff = left + readBuff if left
					readBuff.each_line rs do |ln|
						if ln.byteslice(-lstC.bytesize..-1) == lstC
							ret = chomp ? ln.byteslice(0...-lstC.bytesize) : ln
							@_residue = readBuff.byteslice(ln.bytesize .. -1)
							@_residue = nil if @_residue.bytesize == 0
							return ret
						else
							left = ln
							break
						end
					end
				}
				readSz = readBuff.bytesize
				getln.call if readSz > 0
				if limit
					while readSz < limit
						Fiber.select self, :read
						read_nonblock([rsz, limit - readSz].min, readBuff)
						readSz += readBuff.bytesize
						getln.call
					end
				else
					loop do
						Fiber.select self, :read
						read_nonblock(rsz, readBuff)
						getln.call
					end
				end
			rescue EOFError => err
				return left if left
				raise err
			end
		else
			_org_readline *ag, chomp: chomp, **opts
		end
	end
 
	alias _org_readlines readlines
	def readlines *ag, chomp: false, **opts
		if _use_select?
			limit = ag[0]._?{_1.is_a?(Integer)} || ag[1]._?{_1.is_a?(Integer)}
			rs = ag[0]._?{_1.is_a?(String)} || ag[1]._?{_1.is_a?(String)} || $/
			readBuff = ""
			lstC = rs != "" ? rs : $/ * 2
			res = []
			rsz = limit ? [BUF_SZ, limit].min : BUF_SZ
			left = nil
			begin
				push_each = ->{
					readBuff = left + readBuff if left
					readBuff.each_line rs do |ln|
						if ln.byteslice(-lstC.bytesize..-1) == lstC
							res.push chomp ? ln.byteslice(0...-lstC.bytesize) : ln
							left = nil
						else
							left = ln
						end
					end
				}
				if limit
					readSz = 0
					while readSz < limit
						Fiber.select self, :read
						read_nonblock([rsz, limit - readSz].min, readBuff)
						readSz += readBuff.bytesize
						push_each[]
					end
				else
					loop do
						Fiber.select self, :read
						read_nonblock(rsz, readBuff)
						push_each[]
					end
				end
			rescue EOFError
				res.push left if left
			end
		else
			res = _org_readlines *ag, chomp: chomp
		end
		res
	end
 
 	alias _org_ungetbyte ungetbyte
 	def ungetbyte ag
		if _use_select?
			if ag.is_a?(Integer) && 0 <= ag && ag <= 255
				@_residue += ag.chr
			elsif ag.is_a? String
				@_residue += ag
			else
				raise ArgumentError.new("ungetbyte(ag = '#{ag.inspect}') failed, because ag is neither String nor Integer(0..255).")
			end
 		else
 			_org_ungetbyte ag
 		end
 	end
 	
 	alias _org_ungetc ungetc
 	def ungetc ag
		if _use_select?
	 		case ag
	 		when Integer
	 			@_residue += ag.chr
	 		when String
	 			@_residue += ag
	 		end
	 	else
	 		_org_ungetc ag
	 	end
 	end
 	
 	alias _tell_pos tell
 	def tell
		if _use_select?
 			_tell_pos - @_residue.bytesize
 		else
 			_tell_pos
 		end
 	end
 	
 	alias _org_pos pos
 	def pos
		if _use_select?
 			_org_pos - @_residue.bytesize
 		else
 			_org_pos
 		end
 	end

 	alias _org_pos= pos=
 	def pos= arg
 		ret = (_org_pos = arg)
		if _use_select?
			@_residue = nil
 		end
 		ret
 	end
 	
 	alias _org_seek seek
 	def seek *args
 		ret = _org_seek *args
		if _use_select?
			@_residue = nil
 		end
 		ret
 	end
 	

 	alias _org_print print
	def print *args
		if _use_select?
			buff = args.map(&:to_s).inject(&:+)
			wsz = 0
			while wsz < buff.bytesize
				Fiber.select self, :write
				wsz += write_nonblock(buff.byteslice(wsz, buff.bytesize - wsz))
			end
		else
			_org_print *args
		end
	end


 	alias _org_printf printf
	def printf *args
		if _use_select?
			buff = sprintf *args
			wsz = 0
			while wsz < buff.bytesize
				Fiber.select self, :write
				wsz += write_nonblock(buff.byteslice(wsz, buff.bytesize - wsz))
			end
		else
			_org_print *args
		end
	end

 	alias _org_putc putc
	def putc c
		if _use_select?
			buff = (case c
			when Integer
				(c % 256).chr
			when String
				c[0]
			else
				(c.to_i % 256).chr
			end)
			wsz = 0
			while wsz < buff.bytesize
				Fiber.select self, :write
				wsz += write_nonblock(buff.byteslice(wsz, buff.bytesize - wsz))
			end
		else
			_org_putc *args
		end
	end


 	alias _org_puts puts
	def puts *args
		if _use_select?
			require 'stringio'
			sio = Stringio.new "", "w"
			sio.puts *args
			buff = sio.string
			wsz = 0
			while wsz < buff.bytesize
				Fiber.select self, :write
				wsz += write_nonblock(buff.byteslice(wsz, buff.bytesize - wsz))
			end
		else
			_org_puts *args
		end
	end


 	alias _org_write write
	def write *args
		if _use_select?
			buff = args.map(&:to_s).inject(&:+)
			wsz = 0
			while wsz < buff.bytesize
				p
				Fiber.select self, :write
				p
				wsz += write_nonblock(buff.byteslice(wsz, buff.bytesize - wsz))
			end
		else
			_org_write *args
		end
	end

	perm = Proc.new do |*args|
		ret = []
		(args.length).downto 1 do |i|
			args.permutation(i) do |j|
				ret.push j
			end
		end
		ret += [""]
		ret.join("|")
	end
	RWAMODE_REG = /w(#{perm['\+', '[tb]', 'x']})|[ra](#{perm['\+', '[tb]']})/

	alias _org_reopen reopen
	def reopen *args
		ret = nil
		case args
		in [IO => io, *mode]
			ret = _org_reopen io, *mode
		in [path, *mode]
			m = mode[0]
			case m
			when Integer, nil
				m = (m || fcntl(Fcntl::F_GETFL, 0)) | NONBLOCK
			else
				if !defined? FMode
					sm = m.to_s
					if sm =~ /:/
						smf = $`
						enc = ":" + $'
					else
						smf = sm
						enc = ""
					end
					m = 0
					if smf =~ RWAMODE_REG
						m = (case $&[0] + ($&["+"] || "")
						when "r"
							File::RDONLY
						when "w"
							File::WRONLY|File::CREAT|File::TRUNC
						when "a"
							File::WRONLY|File::CREAT|File::APPEND
						when "r+"
							File::RDWR
						when "w+"
							File::RDWR|File::CREAT|File::TRUNC
						when "a+"
							File::RDWR|File::CREAT|File::APPEND
						end)
					end
					m |= NONBLOCK
				elsif !m.is_a? FMode
					fm = FMode.new(sm)
				else
					fm = m
				end
			end
			if !fm
				sma = sm ? [sm] : []
				fd = self.class.sysopen path, m
				begin
					io = self.class.for_fd(fd, *sma)
					ret = _org_reopen io
				ensure
					io.close
				end
			else
				fm.nonblock = true
				File.open path, fm do |fp|
					ret = _org_reopen fp
				end
			end
		end
		@_use_select = nil
		@_residue = nil
		ret
	end

end

class File
	alias _org_flock flock
	def flock mode
		r, w = self.class.pipe
		begin
			Thread.new do
				_org_flock mode
				w._org_write "\n"
			end
			Fiber.select r, :read
			r.read(1)
		rescue
			r.close
			w.close
		end
	end
end

require 'socket'
class TCPServer
	alias _org_accept accept
	def accept
		if _use_select?
			Fiber.select self, :read
		end
		_org_accept
	end
end

require 'fiber'

using Friend

class Fiber
	
	friend IO

	class OrderedQueue < Array
		def initialize &prc
			@ev = prc
		end
		alias :_insert_at :insert
		def _insert item, bg = 0, ed = size
			if @ev.call(bg) == @ev.call(ed - 1)
				_insert ed - 1, item
			else
				if ed - bg == 1
					_insert_at ed, item
				elsif ed - bg == 2
					_insert_at ed - 1, item
				else
					m = (bg + ed).div 2
					if @ev.call(item) < @ev.call(self[m])
						_insert item, bg, m + 1
					elsif @ev.call(self[m + 1]) <= @ev.call(item)
						_insert item, m + 1, ed
					else
						_insert_at m + 1, item
					end
				end
			end
		end
		def insert item
			if size == 0
				push item
			else
				if @ev.call(self[0]) > @ev.call(item)
					unshift item
				elsif @ev.call(self[-1]) <= @ev.call(item)
					push item
				else
					_insert item
				end
			end
		end
	end

	class Terminate < Exception
	end

	attr_reader :mode, :io, :timeout, :token, :preceeded, :fiber
	List = Hash.new{|h, k| h[k] = Set.new}

	class << self
		def fork *modes, &prc # mode : true, execute block first
			p
			fi = modes.index :first
			li = modes.index :late
			if !li
				first = true
			elsif !fi
				first = false
			elsif fi > li
				first = true
			else
				first = false
			end
			auto_cleanup = modes.include?(:auto_cleanup) ? :auto_cleanup : nil
			p prc
			fb = new do
				begin
					begin
						p :yellow
						prc.call
						p :cyan
					rescue Fiber::Terminate
						p :red
#					rescue Exception => ex
#						p :blue
#						p ex
						#ex.instance_eval {
						#	::STDERR.write "#{backtrace[0]}:#{ex} (#{self.class})".ln
						#	backtrace[1..-1].each do |e|
						#		::STDERR.write("   " + e.ln)
						#	end
						#}
#						p
#						@aborted = true
						#abort
#						raise
					end
				ensure
					current.delete
				end
				p :blue
				doSelect #never retrun
			end
			forked = fb.set_params first ? :start : :pass, auto_cleanup
			p current
			doSelect
			#end
			p forked
			forked
		end

		#private
		
		friend IO, Fiber
		def select_it *args
			self.current.set_params *args
			if doSelect == :terminate
				raise Terminate.new
			end
		end
		def select io, mode, timeout = nil
			io.__fiber__ = current
			select_it mode, io, timeout
		end

		def doSelect
			wios = []
			rios = []
			active_fibers = []
			hasTimer = false
			list.reject{!_1.alive?}
			list.each do |fiber|
				if fiber.timeout
					hasTimer = true
					break
				end
			end
			now = Time.now if hasTimer
			tmout, passFiber = nil
			tmoutList = []
			list.each do |fiber|
				p fiber.selected?, fiber.mode, fiber.preceeded
				next if fiber.preceeded
				case fiber.selected? || fiber.mode
				when :read, :write
					if fiber.mode == :read
						rios.push fiber.io
					else # :write
						wios.push fiber.io
					end
					if fiber.timeout
						if !tmout || (tmout != 0 and tmout > fiber.timeout - now and tmoutList.clear)
							tmout = fiber.timeout - now
							tmout = 0 if tmout < 0
						end 
					end
				when :timer
					if !tmout
						tmout = fiber.timeout - now
						tmout = 0 if tmout < 0
						tmoutList.push fiber
					elsif tmout == 0 && fiber.timeout - now <= 0
						tmoutList.push fiber
					elsif tmout == fiber.timeout - now
						tmoutList.push fiber
					elsif tmout > fiber.timeout - now
						tmout = fiber.timeout - now
						tmout = 0 if tmout < 0
						tmoutList.clear
						tmoutList.push fiber
					end
				when :stop
					# do nothing
				when :terminate, :start, true
					if !tmout
						tmout = 0
						tmoutList.push fiber
					elsif tmout == 0
						tmoutList.push fiber
					else
						tmout = 0
						tmoutList.clear
						tmoutList.push fiber
					end
				when :pass
					passFiber = fiber
					fiber.set_params :start
				else # token
					# do nothing
				end
			end
			p tmout
			p current
			p [rios, wios, tmoutList]
			if rios.size + wios.size + tmoutList.size == 0
				p
				if passFiber
					p passFiber
					tmoutList.push passFiber
				else
					p
					raise Exception.new("no selectable Fiber")
				end
			end
			p
			selectedList, srios, swios, seios = nil
			if ((!tmout && rios.size + wios.size > 0) || (tmout && tmout != 0)) 
				p 
				begin
					p tmout, wios, rios
					srios, swios, seios = IO.select rios, wios, rios + wios, tmout
				rescue Errno::EINTR
					retry
				end
				now = nil
				timeouted = (!srios || srios.size == 0) && (!swios || swios.size == 0)
				[[rios, srios], [wios, swios]].each do |ios, sios|
					ios.each do |io|
						e = io.__fiber__
						if (sios && sios.include?(io)) || (e.timeout && e.timeout < (now ||= Time.now))
							e.set_selected
							(selectedList ||= []).push e
						end
					end
				end
			else #tmout = 0
				p
				timeouted = true
			end
			p srios
			p swios
			p seios
			p selectedList
			p tmoutList
			if timeouted
				(selectedList ||= []).push *tmoutList
			end
			current_fiber = selectedList.shuffle[0]
			current_fiber.reset_selected if current_fiber.selected?
			p current_fiber
			current_fiber.continue
		end
		def list
			List[Thread.current]
		end

		public

		def pass
			select_it :pass
		end
		def sleep t = :stop
			p :purple
			select_it t
			p :purple
		end
		def stopBy token, timeout = :stop
			res = select_it token, timeout
			if res == :start
				:timeout
			else
				token
			end
		end
		def awakeBy token
			list.each do |fiber|
				if fiber.token == token
					fiber.set_params :start
				end
			end
			select_it :start
		end
		def timer t
			loop do
				yield
				sleep t
			end
		end
		def waitall
			p.red
			while list.size > 1
				p.red list
				doSelect
			end
			p.red
			if list.to_a[0] != Fiber.current
				raise Exception.new("Unknown Exception : last fiber is not current fiber")
			end
		end
	end

	#private
	def check_initialized
		if !self.class.list.include? self
			self.class.list.add self
			if block_given?
				yield
			end
			@mutexStack ||= []
			@lockStat ||= []
			@mutexList ||= Hash.new{|h, k| h[k] = 0}
			@preceeded ||= false
		end
		self
	end
	def delete
		self.class.list.delete self
	end
	def set_params *args
		check_initialized
		@mode, @timeout, @io, @token, @selected = nil
		args.each do |e|
			case e
			when :auto_cleanup
				@auto_cleanup = true
			when Symbol
				@mode = e
			when Time
				@timeout = e
			when Numeric
				@timeout = Time.now + e
			when IO
				@io = e
			when nil
			else
				@token = e
			end
		end
		@timeout and @mode ||= :timer
		self
	end

	at_exit do
		Fiber.current.delete
	end

	def auto_cleanup?
		@auto_cleanup
	end
	def set_awake
		set_params :start
	end
	def set_preceeded
		@preceeded = true
	end
	def reset_preceeded
		@preceeded = false
	end
	def set_selected
		@selected = true
	end
	def reset_selected
		@selected = false
	end
	def selected?
		return @selected
	end
	def continue arg = nil
		@mutexStack.each do |e|
			if e.has_semi_lock_fiber self
				e.lock self
			end
		end
		m = arg || @mode
		@mode, @timeout, @token = nil
		if Fiber.current != self
			p.bgGreen Fiber.current.mode, Fiber.current, self, btrace[0..3]
			if Fiber.current.mode == nil
				Fiber.current.set_params :start
			end
			transfer m
		else
			p.bgGreen self, :continue, btrace[0..3]
		end
	end

	public
	def awake_at t = 0
		set_params t
	end
	def terminate
		if Fiber.current == self
			raise Terminate.new
		end
		set_params :terminate
		Fiber.select_it :pass
	end
	def awake
		set_params :start
		Fiber.select_it :pass
	end

	class Mutex
		#private
		def initialize
			@stopped = {}
			@semi_lock_fibers = Hash.new{|h, k| h[k] = 0}
			@waiting_fibers = Hash.new
		end
		def lock fiber
			while @fiber && @fiber != fiber
				@waiting_fibers[fiber] = true
				Fiber.sleep
			end
			@fiber = fiber
			@semi_lock_fibers.keys.each do |e|
				if e != fiber
					e.set_preceeded
				end
			end
			@fiber.reset_preceeded
		end
		def unlock fiber
			if @fiber == fiber
				@semi_lock_fibers.keys.each do |e|
					if e != self
						e.reset_preceeded
					end
				end
				@waiting_fibers.each do |e|
					e.set_awake
				end
				@fiber = nil
			end
		end
		def set_semi_lock_fiber fiber
			@semi_lock_fibers[fiber] += 1
		end
		def reset_semi_lock_fiber fiber
			if @semi_lock_fibers.key? fiber
				tmp = (@semi_lock_fibers[fiber] -= 1)
				if tmp <= 0
					@semi_lock_fibers.delete fiber
				end
			end
		end
		def has_semi_lock_fiber fiber
			@semi_lock_fibers.key? fiber
		end
		public
		def synchronize mode = :normal, &prc
			Fiber.current.mutexSync self, mode, &prc
		end
	end
	friend Mutex
	#private
	def mutexSyncLock
		mutex = @mutexStack[-1]
		if !@lockStat[-1]
			@lockStat[-1] = true
			mutex.lock self
		end
	end
	def mutexSyncUnlock
		mutex = @mutexStack[-1]
		mutex.unlock self
	end
	def mutexSync mutex, mode
		res = nil
		begin
			@mutexList[mutex] += 1
			@mutexStack.push mutex
			@lockStat.push false
			case mode
			when :semi
				mutex.set_semi_lock_fiber self
			else
				mutexSyncLock
			end
			begin
				res = yield
			ensure
				mutexSyncUnlock
			end
		ensure
			tmp = (@mutexList[mutex] -= 1)
			if tmp == 0
				@mutexList.delete mutex
			end
			@mutexStack.pop
			@lockStat.pop
			res
		end
	end

#	STDIN = Fiber.new ::STDIN
#	STDOUT = Fiber.new ::STDOUT
#	STDERR = Fiber.new ::STDOUT
#	def tmode= m
#		@mode = m
#	end
#	def tmode
#		@mode
#	end
	
	at_exit do
		p :cyan, $!
		if $! && !$!.is_a?(SystemExit)
#			$!.instance_eval {
#				STDERR.write "#{backtrace[0]}:#{$!} (#{self.class})".ln
#				backtrace[1..-1].each do |e|
#					STDERR.write "   " + e.ln
#				end
#			}
			@aborted = true
#			abort
		end
		p Fiber::List.size
		toTerm = []
		Fiber::List.each do |t, fibers|
			fibers.each do |fiber|
				if fiber.auto_cleanup?
					toTerm.push fiber
				end
			end
		end
		p toTerm
		p Fiber::List.size
		toTerm.each &:terminate
		p Fiber::List.size
		if !@aborted && Fiber::List.size > 1
			p Fiber::List
			raise Exception.new("#{Fiber::List.size - 1} Fiber procedure(s) not cleaned")
		end
		p
	end
end

Fiber.current.set_params :start



