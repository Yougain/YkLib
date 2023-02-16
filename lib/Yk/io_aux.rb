

require 'tempfile'
require 'Yk/__hook__'
require 'fcntl'
require 'Yk/ioctl'



if !ENV['HOME']
	require 'etc'
	Etc.getpwuid(Process.uid).then do |w|
		if w.dir == "/"
			if !File.exist?(w = "/var/tmp/" + w.name)
				Dir.mkdir w
			end
		else
			w = w.dir
		end
		ENV['HOME'] = w
	end
end
(ENV['HOME'] + "/.tmp").then do |w|
	if !File.exist? w
		Dir.mkdir w
	end
end


begin
	require 'io/nonblock'
rescue LoadError
	class IO
		def nonblock?
			fcntl(Fcntl::F_GETFL) & Fcntl::O_NONBLOCK == Fcntl::O_NONBLOCK
		end
		def nonblock= (arg)
			fl = fcntl(Fcntl::F_GETFL)
			if arg
				fcntl(Fcntl::F_SETFL, fl | Fcntl::O_NONBLOCK)
			else
				fcntl(Fcntl::F_SETFL, fl & ~Fcntl::O_NONBLOCK)
			end
			arg
		end
		def nonblock (arg = true)
			nblk = (flg = fcntl(Fcntl::F_GETFL)) & Fcntl::O_NONBLOCK == Fcntl::O_NONBLOCK
			if nblk
				if arg
					yield
				else
					begin
						fcntl(Fcntl::F_SETFL, flg & ~Fcntl::O_NONBLOCK)
						yield
					ensure
						fcntl(Fcntl::F_SETFL, fl | Fcntl::O_NONBLOCK)
					end
				end
			else
				if arg
					begin
						fcntl(Fcntl::F_SETFL, fl | Fcntl::O_NONBLOCK)
						yield
					ensure
						fcntl(Fcntl::F_SETFL, flg & ~Fcntl::O_NONBLOCK)
					end
				else
					yield
				end
			end
		end
	end
end


class IO
	OPEN_OPTS___ = %W{
		path
		file 
		mode_enc
		perm
		mode

		external_encoding
		internal_encoding
		encoding
		textmode
		binmode
		autoclose

		execopt

		command
		env

		args
		arg0
		cmdname

		unsetenv_others
		pgroup
		chdir
		umask
		close_others
		exception

		in
		out
		err
		program
		args
		options

		pid
		user
		su
		sudo
	}.map{|e| e.intern}
	alias_method :__org_read__, :read
	def read *args, **opts, &bl
		if args[0].is_a?(Integer) && args[1].is_a?(Integer)
			pos = args[1]
			args.delete_at(1)
			__org_read__ *args, **opts, &bl
		else
			__org_read__ *args, **opts, &bl
		end
	end
	def foreach (rs = $/, chomp: false)
		each_line rs, chomp: chomp do |ln|
			yield ln
		end
	end
	def self.read_12_each *args, **opts
		popts = delete_open_opts opts
		r, w = IO.pipe
		r2, w2 = IO.pipe
		fork do
			STDOUT.reopen w
			STDERR.reopen w2
			if args[0].is_a? Array
				exec *args[0], **opts
			else
				exec *args, **opts
			end
		end
		w.close
		w2.close
		b = ""
		b2 = ""
		rsels = [r, r2]
		loop do
			rs, = IO.select rsels
			if rs.include?(r)
				c = nil
				begin
					c = r.read_nonblock(1024)
				rescue EOFError
					rsels.delete r
					if rsels.empty?
						return [b, b2]
					end
				end
				b += c if c
			end
			if rs.include?(r2)
				c = nil
				begin
					c = r2.read_nonblock(1024)
				rescue EOFError
					rsels.delete r2
					if rsels.empty?
						return [b, b2]
					end
				end
				b2 += c if c
			end
		end
	end
	def self.read_each_line (rs = $/, chomp: false)
		foreach rs, chomp: chomp do |ln|
			yield ln
		end
	end
	def pipe?
		if !defined? @pipe
			begin
				tell
				@pipe = false
			rescue Errno::ESPIPE
				@pipe = true
			end
		end
		@pipe
	end
	def readln (rs = $/)
		gets(rs)
	end
	def read_each_line (rs = $/, chomp: false)
		each_line rs, chomp: chomp do |ln|
			yield ln
		end
	end
	def writeln (*args)
		b = 0
		args.each do |ln|
			b += write ln.chomp + "\n"
		end
		b
	end
	def writelnF (*args)
		b = writeln *args
		flush
		b
	end
	def writeF (*args)
		b = write *args
		flush
		b
	end
	def println (*args)
		args.each do |ln|
			print ln.chomp + "\n"
		end
		nil
	end
	def printF (*args)
		print *args
		flush
		nil
	end
	def printlnF (*args)
		println *args
		flush
		nil
	end
	def printf (*args)
		print sprintf(*args)
		nil
	end
	def printfln (*args)
		print sprintf(*args) + "\n"
		nil
	end
	def printfF (*args)
		printF sprintf(*args)
		nil
	end
	def printflnF (*args)
		printlnF sprintf(*args)
		nil
	end
	def rewrite_each_line
		if !pipe?
			newLines = []
			modPos = nil
			ln = nil
			lnNew = nil
			pushNewLine = Proc.new do
				lnNew != "" && lnNew[-1] != ?\n && lnNew += "\n"
				newLines.push lnNew
			end
			each_line do |ln|
				lnNew = yield ln
				if newLines.size == 0
					if lnNew != ln
						modPos = pos - ln.size
						pushNewLine.call
					end
				else
					pushNewLine.call
				end
			end
			if (lnNew = yield("")) != ""
				if modPos == nil
					modPos = pos
				end
				if ln != nil && ln[-1] != ?\n
					lnNew = "\n" + lnNew
				end
				pushNewLine.call
			end
			if newLines.size > 0
				seek modPos
				newLines.each do |e|
					write e
				end
				truncate pos
			end
		else
			out = self == STDIN ? STDOUT : self
			each_line do |ln|
				out.writeF yield(ln)
			end
		end
	end
	def addline *args
		regs = args.map{ |e| Regexp.new '\s*' + e.strip.split.map{ |f| Regexp.escape(f) }.join('\s+') + '\s*' }
		hash = Hash.new
		prevLn = nil
		rewrite_each_line do |ln|
			regs.each_index do |i|
				if ln =~ regs[i]
					hash[i] = true
					break
				end
			end
			if ln == ""
				ln = (!prevLn || (prevLn[-1] == ?\n)) ?  "" : "\n"
				args.each_index do |i|
					if !hash[i]
						ln += args[i].chomp + "\n"
					end
				end
			end
			prevLn = ln
			ln
		end
	end
	def addlines *a
		addline *a
	end
	def delline *args
		regs = args.map{ |e| Regexp.new '\s*' + e.strip.split.map{ |f| Regexp.escape(f) }.join('\s+') + '\s*' }
		rewrite_each_line do |ln|
			regs.each_index do |i|
				if ln =~ regs[i]
					ln = ""
					break
				end
			end
			ln
		end
	end
	def dellines *a
		delline *a
	end
	def ref_each_line
		if !pipe?
			newLines = []
			modPos = nil
			ln = nil
			lnNew = nil
			pushNewLine = Proc.new do
				lnNew != "" && lnNew[-1] != ?\n && lnNew += "\n"
				newLines.push lnNew
			end
			each_line do |ln|
				lnNew = ln.clone
				yield lnNew
				if newLines.size == 0
					if lnNew != ln
						modPos = pos - ln.size
						pushNewLine.call
					end
				else
					pushNewLine.call
				end
			end
			lnNew = ""
			yield(lnNew)
			if lnNew != ""
				if modPos == nil
					modPos = pos
				end
				if ln != nil && ln[-1] != ?\n
					lnNew = "\n" + lnNew
				end
				pushNewLine.call
			end
			if newLines.size > 0
				seek modPos
				newLines.each do |e|
					write e
				end
				truncate pos
			end
		else
			out = self == STDIN ? STDOUT : self
			each_line do |ln|
				yield ln
				out.writeF ln
			end
		end
	end
	def writeln_readln (*args)
		if !pipe?
			raise Exception.new("cannot use writeln_readln for non-pipe IO")
		end
		_in = self == STDOUT ? STDIN : self
		res = []
		args.each do |e|
			t = Thread.new do
				res.push _in.readln
			end
			writelnF e
			t.join
		end
		return *res
	end
end


def println (*args)
	STDOUT.writeln *args
	nil
end
def printF (*args)
	STDOUT.writeF *args
	nil
end
def printlnF (*args)
	STDOUT.writelnF *args
	nil
end
def err (*args)
	STDERR.write *args
	nil
end
def errln (*args)
	STDERR.writeln *args
	nil
end
def errF (*args)
	STDERR.writeF *args
	nil
end
def errlnF (*args)
	STDERR.writelnF *args
	nil
end


def IO.nonblock
	@nonblock
end


def IO.nonblock= (arg)
	@nonblock = arg
	STDIN.closed? or STDIN.nonblock = arg
	STDOUT.closed? or STDOUT.nonblock = arg
	STDERR.closed? or STDERR.nonblock = arg
end
begin
	IO.nonblock = false
rescue Errno::EBADF
end

class IO
	begin
		require 'termios'
	rescue LoadError
	else
		def stty_mode
			Termios::tcgetattr(self).lflag
		end
		def stty_mode= (arg)
			tmp = Termios::tcgetattr(self)
			tmp.lflag = arg
			Termios::tcsetattr(self,Termios::TCSANOW, tmp)
			arg
		end
		def set_raw
			old = (tmp = Termios::tcgetattr(self)).clone
			tmp.lflag
			tmp.iflag &= ~(Termios::IGNBRK | Termios::BRKINT | Termios::PARMRK | Termios::ISTRIP | Termios::INLCR | Termios::IGNCR | Termios::ICRNL | Termios::IXON);
			tmp.oflag &= ~Termios::OPOST;
			tmp.lflag &= ~(Termios::ECHO | Termios::ECHONL | Termios::ICANON | Termios::ISIG | Termios::IEXTEN);
			tmp.cflag &= ~(Termios::CSIZE | Termios::PARENB);
			tmp.cflag |= Termios::CS8 #| Termios::CREAD | Termios::CLOCAL;
			#tmp.cflag &= ~Termios::ICANON
			Termios::tcsetattr(self,Termios::TCSAFLUSH, tmp)
			if block_given?
				begin
					yield
				ensure
					Termios::tcsetattr(self,Termios::TCSAFLUSH, old)
				end
			else
				old
			end
		end
		def set_for_password
			old = (tmp = Termios::tcgetattr(self)).clone
			tmp.lflag &= ~Termios::ECHO
			tmp.lflag |= Termios::ECHONL
			Termios::tcsetattr(self,Termios::TCSAFLUSH, tmp)
			if block_given?
				begin
					yield
				ensure
					Termios::tcsetattr(self,Termios::TCSAFLUSH, old)
				end
			else
				old
			end
		end
		def prompt_password prompt
			write prompt
			flush
			set_for_password do
				gets.strip
			end
		end
		def attr
			Termios::tcgetattr(self)
		end
		def attr= (arg)
			Termios::tcsetattr(self,Termios::TCSANOW, arg)
		end
	end
	class WinSize
		def initialize (r, c, w, h)
			@row = r
			@col = c
			@width = w
			@height = h
		end
		attr :row, true
		attr :col, true
		attr :width, true
		attr :height, true
		def to_s
			[@row, @col, @width, @height].pack("S*")
		end
		def clone
			WinSize.new(@row, @col, @width, @height)
		end
	end
	def winsz
		buff = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
		ioctl(Ioctl::TIOCGWINSZ, buff)
		WinSize.new *buff.unpack("S*")[0..3]
	end
	def winsz= (arg)
		ioctl(Ioctl::TIOCSWINSZ, arg.to_s)
		arg
	end
	class FMode
		def clone
			self.class.new self
		end
		def to_fmode
			self.class.new self
		end
		def to_i
			@fmode
		end
		def | (arg)
			arg = arg.to_fmode
			FMode.new(@fmode | arg.to_i)
		end
		def for_pipe
			FMode.new(@fmode & File::NONBLOCK)
		end
		def read_only
			FMode.new(@fmode & ~(File::WRONLY|File::RDWR))
		end
		def write_only
			FMode.new((@fmode & ~File::RDWR) | File::WRONLY)
		end
		def inspect
			[readable? && "r", writable? && "w", nonblock?, lock?, @fmode].inspect
		end
		def std_mode
			ret = @rwamode
			if !ret
				if @fmode & (File::RDWR|File::APPEND) == File::RDWR|File::APPEND
					ret = "a+"
				elsif @fmode & (File::RDWR|File::TRUNC) == File::RDWR|File::TRUNC
					ret = "w+"
				elsif @fmode & File::RDWR == File::RDWR
					ret = "r+"
				elsif @fmode & File::APPEND == File::APPEND
					ret = "a"
				elsif @fmode & File::WRONLY == File::WRONLY
					ret = "w"
				else
					ret = "r"
				end
			end
			ret += "x" if @xmode
			ret += @encode if @encode
			ret
		end
		attr_reader :fmode, :createP, :tbmode, :encode, :rwamode, :xmode, :progStdout, :progStdin, :progStderr, :sysmode, :pmode, :flock, :delete
		def stdin?
			@progStdin
		end
		def stdout?
			@progStdout
		end
		def stderr?
			@progStderr
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
		def initialize (arg = "")
			#if arg == "" || arg == nil
			#	arg = "r"
			#end
			if arg.is_a? String
				if arg =~ /:/
					arg = $`
					@encode = ":" + $'
				end
				arg = arg.dup
				rwamode, tbmode, xmode, nbmode, crmode, ppmode, termmode = nil
				if arg =~ RWAMODE_REG
					rwamode = $&[0]
					rwamode += $&["+"] || ""
					tbmode = $&["t"] || $&["b"]
					xmode = $&["x"]
					arg.delete! $&
				end
				#rwamode ||= "r"
				@rwamode = rwamode
				["B", "N"].each do |e|
					if i = arg.index(e)
						nbmode = arg.slice!(i..i)
						break
					end
				end
				!nbmode and nbmode = IO.nonblock ? "n" : "b"
				i = arg.index("c") and crmode = arg.slice!(i..i)
				["P", "p"].each do |e|
					if i = arg.index(e)
						ppmode = arg.slice!(i..i)
						break
					end
				end
				lmode = nil
				["l", "s", "e"].each do |e|
					if i = arg.index(e)
						lmode = arg.slice!(i..i)
						break
					end
				end
				i = arg.index("d") and dlmode = arg.slice!(i..i)
				i = arg.index("S") and sysmode = arg.slice!(i..i)
				i = arg.index("1") and stdout = arg.slice!(i..i)
				i = arg.index("2") and stderr = arg.slice!(i..i)
				i = arg.index("T") and ppmode = arg.slice!(i..i)
				arg != "" and raise ArgumentError.new("extra fmode '#{arg}' specified")
				case rwamode
				when "r"
					@fmode = File::RDONLY
				when "w"
					@fmode = File::WRONLY|File::CREAT|File::TRUNC
				when "a"
					@fmode = File::WRONLY|File::CREAT|File::APPEND
				when "r+"
					@fmode = File::RDWR
				when "w+"
					@fmode = File::RDWR|File::CREAT|File::TRUNC
				when "a+"
					@fmode = File::RDWR|File::CREAT|File::APPEND
				end
				@tbmode = tbmode
				if @tbmode == "b"
					@fmode |= File::BINARY
				end
				@fmode |= File::EXCL if xmode
				@xmode = xmode
				case nbmode
				when "N"
					@fmode |= File::NONBLOCK
				end
				case crmode
				when "c"
					@fmode |= File::CREAT
				end
				case ppmode
				when "p"
					if readable?
						@progStdout = true
						if stderr
							@progStderr = true
							stdout or @progStdout = false
						end
					end
					if writable?
						@progStdin = true
					end
					@fmode &= ~(File::CREAT|File::APPEND|File::TRUNC)
					@pmode = :program
				when "T"
					@fmode &= ~(File::CREAT|File::APPEND|File::TRUNC)
					@fmode |= File::RDWR
					@pmode = :terminal
				when "P"
					if @fmode & File::CREAT == File::CREAT
						@createP = true
					end
					#@fmode &= ~(File::CREAT|File::APPEND|File::TRUNC) # for interavitve pipe, we use File::TRUNC
					@pmode = :pipe
				end
				case lmode
				when "l"
					@flock = writable? ? File::LOCK_EX : File::LOCK_SH
				when "e"
					@flock = File::LOCK_EX
				when "s"
					@flock = File::LOCK_SH
				end
				sysmode and @sysmode = true
				dlmode and @delete = true
			elsif arg.is_a? Integer
				@fmode = arg
			elsif arg.is_a? FMode
				@fmode = arg.fmode
				@flock = arg.flock
				@pmode = arg.pmode
				@sysmode = arg.sysmode
				@createP = arg.createP
				@delete = arg.delete
				@progStdin = arg.progStdin
				@progStdout = arg.progStdout
				@progStderr = arg.progStderr
				@tbmode = arg.tbmode
				@encode = arg.encode
				@rwamode = arg.rwamode
				@xmode = arg.xmode
			else
				@fmode = 0
			end
		end
		def normal? # without extra mode defined by path_aux.rb
			!@flock && !@pmode && !@createP && !@delete && !@progStdin && !@progStdout && !@progStderr
		end
		def pmode
			@pmode
		end
		def pmode= (arg)
			@pmode = arg
		end
		def terminal?
			@pmode == :terminal
		end
		def sys?
			@sysmode
		end
		def lock?
			@flock
		end
		def delete?
			@delete
		end
		def delete= (arg)
			@delete = arg
		end
		def lock= (arg)
			case arg
			when true
				if !@flock
					if writable?
						@flock = File::LOCK_EX
					else
						@flock = File::LOCK_SH
					end
				end
			when "l"
				if writable?
					@flock = File::LOCK_EX
				else
					@flock = File::LOCK_SH
				end
			when "s"
				@flock = File::LOCK_SH
			when "e"
				@flock = File::LOCK_EX
			when nil, false
				@flock = nil
			else
				raise ArgumentError.new("illeagal lock flag '#{arg}'")
			end
		end
		def to_flock
			@flock
		end
		def coerce (other)
			if other.is_a? String
				[self.class.new(other).to_i, @fWRMode]
			end
		end
		def reverse!
			if @fmode & File::RDWR != File::RDWR
				if @fmode & File::WRONLY == File::WRONLY
					@fmode &= ~(File::WRONLY)
				else
					@fmode |= File::WRONLY
				end
			end
			self
		end
		def clone
			FMode.new(fmode)
		end
		def reverse
			clone.reverse!
		end
		def writable?
			if @fmode
				@fmode & File::RDWR == File::RDWR || @fmode & File::WRONLY == File::WRONLY
			end
		end
		def writable= (arg)
			if arg
				if !writable?
					if readable?
						@fmode ||= 0
						@fmode |= File::RDWR
					else
						raise Exception.new("internal error: conflict of file flag")
					end
				end
			else
				if writable?
					if readable?
						@fmode ||= 0
						@fmode &= ~(File::RDWR|File::WRONLY)
					else
						raise ArgumentError.new("cannot reset writable flag")
					end
				end
			end
		end
		def readable?
			if @fmode
				@fmode & File::RDWR == File::RDWR || @fmode & File::WRONLY != File::WRONLY
			else
				true
			end
		end
		def readable= (arg)
			if arg
				if !readable?
					if writable?
						@fmode ||= 0
						@fmode &= ~File::WRONLY
						@fmode |= File::RDWR
					else
						raise Exception.new("internal error: conflict of file flag")
					end
				end
			else
				if readable?
					if writable?
						@fmode ||= 0
						@fmode |= File::WRONLY
						@fmode &= ~File::RDWR
					else
						raise ArgumentError.new("cannot reset readable flag")
					end
				end
			end
		end
		def creatable?
			if @fmode
				@fmode & File::CREAT == File::CREAT || @createP
			end
		end
		def creatable= (arg)
			@fmode ||= 0
			if arg
				@fmode |= File::CREAT
			else
				@fmode &= ~File::CREAT
			end
		end
		def append?
			if @fmode
				@fmode & File::APPEND == File::APPEND
			end
		end
		def append= (arg)
			@fmode ||= 0
			if arg
				@fmode |= File::APPEND
			else
				@fmode &= ~File::APPEND
			end
		end
		def nonblock?
			if @fmode
				@fmode & File::NONBLOCK == File::NONBLOCK
			end
		end
		def nonblock= (arg)
			@fmode ||= 0
			if arg
				@fmode |= File::NONBLOCK
			else
				@fmode &= ~File::NONBLOCK
			end
		end
		def truncate?
			if @fmode
				@fmode & File::TRUNC == File::TRUNC
			end
		end
		def truncate= (arg)
			@fmode ||= 0
			if arg
				@fmode |= File::TRUNC
			else
				@fmode &= ~File::TRUNC
			end
		end
	end
	def fmode
		flg = fcntl(Fcntl::F_GETFL)
		flg &= ~(File::RDWR|File::WRONLY)
		readable = nil
		writable = nil
		begin
			readpartial(0)
			readable = true
		rescue IOError => e
			if e.to_s =~ /not opened for reading/
				readable = false
			else
				raise
			end
		end
		begin
			flush
			writable = true
		rescue IOError => e
			if e.to_s =~ /not opened for writing/
				writable = false
			else
				raise
			end
		end
		case [readable, writable]
		when [true, true]
			flg |= File::RDWR
		when [true, false]
		when [false, true]
			flg |= File::WRONLY
		else
			raise Exception.new("unknown error at fmode flag operation")
		end
		FMode.new(flg)
	end
	def readable?
		fmode.readable?
	end
	def writable?
		fmode.writable?
	end
	def write_obj (obj)
		str = Marshal.dump(obj)
		write str
	end
	def read_obj
		Marshal.load(self)
	end
	def each_obj
		while true
			yield Marshal.load(self)
		end
	end
	def fmode= (mode)
		__set_mode = Proc.new do |io, m|
			io.fcntl(Fcntl::F_SETFL, m)
		end
		mode = mode.to_fmode
	end
	def transfer_to (io, termStr = nil)
		toCompare = ""
		Thread.new do
			t = Thread.current
			if io.pid
				Process.set_detach io.pid.to_i do
					t.terminate
				end
			end
			if pid
				Process.set_detach pid.to_i do
					t.terminate
				end
			end
			begin
				buff = ""
				while true
					readpartial 1024, buff
					if termStr
						toCompare += buff
						if toCompare.size >= termStr.size
							if (i = toCompare.index(termStr)) == nil
								toCompare.slice!(0 .. toCompare.size - termStr.size + 1)
							else
								yield
								break
							end
						end
					end
					io.write buff
					io.flush
				end
			rescue EOFError
			end
		end
	end
	def yn? prompt
		write prompt.strip + " <Y/N> ? "
		flush
		res = gets.strip
		if res =~ /^Y(es|)$/i
			true
		else
			false
		end
	end
	def setting_password file = nil, **opts
		p
		if file && ((File.exist?(file) && !File.writable?(file)) || !File.dirname(file).writable?)
			p file
			raise ::ArgumentError.new("cannot write on the file, '#{file}'")
		else
			p
			if opts[:prompt]
				p
				write opts[:prompt]
			else
				p
				write "setting new password: "
			end
			p
			pw = ""
			p
			set_for_password do
				p
				pw = gets.chomp
			end
			p
			if !pw.empty?
				p
				if opts[:reprompt]
					p
					write opts[:reprompt]
				else
					write " retype new password: "
				end
				p
				pw2 = ""
				p
				set_for_password do
					pw2 = io.gets.chomp
				end
				if pw2 != pw
					write opts[:messaage_wrong] || "wrong password.\n"
					return nil
				else
					file&.write pw
					return pw
				end
			else
				if yn? "automatically generate password"
					pwd = genpasswd 12
					file&.write pw
					return pw
				else
					nil
				end
			end
		end
		return nil
	end
	def enter_password_if prompt, pwd
		rexp = case prompt
		when String
			/(#{Regexp.escape(prompt)})$/
		when Regexpr
			/(#{prompt})$/
		end
		buff = ""
		begin
			loop do
				res = IO.select [self], nil, nil, 0.1
				if !res
					if buff =~ rexp
						if pwd
							write pwd.chomp + "\n"
						else
							if TTY.open do |tty|
								pwd = tty.prompt_password prompt
								write pwd.chomp + "\n"
							end;else
								raise Exception.new("Waiting password in background")
							end
						end
					end
				elsif self == res[0][0]
					buff += read_nonblock 1024
					buff.each_line do |ln|
						if ln[-1] == "\n"
							yield ln
						else
							buff = ln
						end
					end
				end
			end
		rescue EOFError
			if !buff.empty?
				yield buff
			end
		end
	end
	def until prompt
		rexp = case prompt
		when String
			/(#{Regexp.escape(prompt)})$/
		when Regexpr
			/(#{prompt})$/
		end
		buff = ""
		begin
			loop do
				res = IO.select [self], nil, nil, 0.1
				if !res
					if buff =~ rexp
						return buff
					end
				elsif self == res[0][0]
					buff += read_nonblock 1024
					buff.each_line do |ln|
						if ln[-1] == "\n"
							yield ln
						else
							buff = ln
						end
					end
				end
			end
		rescue EOFError
			if !buff.empty?
				yield buff
			end
		end
	end
end


class TTY
	def self.open
		if STDIN.tty?
			tty = "/proc/#{$$}/fd/#{STDIN.to_i}".readlink
			File.open tty, "r+" do |io|
				yield io
			end
		else
			nil
		end
	end
	def self.yn? prompt
		open do |io|
			io.yn? prompt
		end
	end
	def self.write arg
		open do |io|
			io.write arg
		end
	end
	def self.writeln arg
		open do |io|
			io.writeln arg
		end
	end
end

class String
	def to_fmode
		IO::FMode.new self
	end
end


class Integer
	def to_fmode
		IO::FMode.new self
	end
end

class << Object.new
	def self.rewriteIOMethods (cls, rewrite_methods)
		cls.class_eval do
			rms = rewrite_methods.sort_by do |a|
				-a.size
			end
			def self.delete_open_opts h
				ret = {}
				toDel = h.keys & IO::OPEN_OPTS___
				h.each do |k, v|
					case k
					when Integer, IO
						toDel.push k
					when k.to_s =~ /^rlimit_/
						toDel.push k
					end
				end
				toDel.each do |k|
					ret[k] = h.delete(k)
				end
				ret
			end
			def self.getLabelAndFm (e, extra = "")
				case e
				when "rewrite_each_line", "ref_each_line", "addlines", "addline", "dellines", "delline"
					fmode = IO::FMode.new extra
					fmode.readable = true
					fmode.writable = true
					fmode.creatable = true
					fmode.truncate = false
				when "writeln_readln"
					fmode = IO::FMode.new extra
					fmode.readable = true
					fmode.writable = true
					fmode.creatable = true
					fmode.truncate = true
				when /write|print/
					fmode = IO::FMode.new extra
					fmode.writable = true
					fmode.readable = false
					fmode.creatable = true
					if !fmode.append?
						fmode.truncate = true
					end
				else
					fmode = IO::FMode.new extra
				end
				[e.to_sym, fmode]
			end
			rms.each do |e|
				e = e.to_sym
				if ![:write, :read, :readlines, :foreach].include? e
					self.__hook__ e, *getLabelAndFm(e) do |org, tlabel, fmode|
						#STDERR.write caller.inspect + "\n"
						#STDERR.flush
						#STDERR.write org.class.inspect + "\n"
						#STDERR.flush
						#STDERR.write org.inspect + "\n"
						#STDERR.flush
						path = org.opts.delete(:path) || org.opts.delete(:file) || org.args.shift
						#STDERR.write path + "\n"
						#STDERR.write fmode.inspect + "\n"
						opts = delete_open_opts(org.opts)
						pid_label = opts.delete :pid
						#STDERR.write e.inspect.ln
						#STDERR.write e.inspect.ln
						#STDERR.write self.inspect.ln
						File.open path, fmode, **opts do |fp|
							if pid_label && fp.respond_to?(:pid)
								require 'Yk/misc_tz'
								binding.of_caller(2).eval("#{pid_label.to_s} = #{pid}")
							end
							fp.method(tlabel).call(*org.args, **org.opts, &org.block)
						end
					end
				end
			end
			self.__hook__ :method_missing do |org|
				name = org.args[0]
				if name != :__hk_org_method_B_missing
					if name.to_s =~ /^(#{rms.join('|')})_/ && (lb, fm = getLabelAndFm($1, $') rescue false)
						(class<<cls;self;end).class_eval do
							define_method name do |*args, **opts, &bl|
								path = opts.delete(:path) || opts.delete(:file) || args.shift
								oopts = delete_open_opts(opts)
								pid_label = opts.delete :pid
								File.open path, fm, **oopts do |fp|
									if pid_label && fp.respond_to?(:pid)
										binding.of_caller(2).eval("#{pid_label.to_s} = #{pid}")
									end
									fp.method(lb).call(*args, **opts, &bl)
								end
							end
						end
						path = org.opts.delete(:path) || org.opts.delete(:file) || org.args[1]
						opts = delete_open_opts(org.opts)
						pid_label = opts.delete :pid
						File.open path, fm, **opts do |fp|
							if pid_label && fp.respond_to?(:pid)
								require 'Yk/misc_tz'
								binding.of_caller(2).eval("#{pid_label.to_s} = #{pid}")
							end
							fp.method(lb).call(*org.args[2..-1], **org.opts, &org.block)
						end
					else
						org.call
					end
				else
					__reraise_method_missing name
				end
			end
			self.__hook__ :respond_to_missing? do |org|
				name = org.args[0]
				if name.to_s =~ /^(#{rms.join('|')})_/ && (fm = IO::FMode.new($') rescue false)
					true
				else
					org.call
				end
			end
		end
	end
	rewriteIOMethods(IO, 
		%w{
			read gets readline readlines foreach write
			readln writeln read_each_line rewrite_each_line ref_each_line
			writeln_readln print println printf printfln addline delline addlines dellines
		}
	)
end






