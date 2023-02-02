require 'Yk/path_aux'
require 'net/smtp'
require 'base64'
require 'uri'
require 'net/dns'
require 'socket'
require 'cgi'


#p > nil


IPv4Regexp = /^(([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]).){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/


class IO
	def set_sio mode = nil
		@sio = SIO.new self, mode
	end
	def sio
		@sio
	end
end


class String
	SIOServers = Hash.new
	TCPConnectTimeout = 1
	def to_ip
		SIOResolver.resolv self
	end
	def __open tmode, &prc
		self =~ /:/
		adr, port = $`, $'
		a = adr
		p adr
		if adr !~ /^(([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]).){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/
			p
			adr = adr.to_ip
			p
		end
		if !adr
			raise Exception.new("cannot resolv address: #{a}")
		end
		p adr
		s = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
		sock_addr = Socket.sockaddr_in(port, adr)
		s.set_sio tmode
		s.connect_nonblock(sock_addr) rescue IO::WaitWritable
		SIO.select s.sio, :write, TCPConnectTimeout
		opt = s.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR)
		p opt
		if opt.int != 0
			s.close
			raise SystemCallError.new(opt.int)
		end
		if prc
			begin
				prc.call s.sio
			ensure
				s.sio.close
			end
		else
			s.sio
		end
	end
	def open_T &prc
		__open :text, &prc
	end
	def open &prc
		__open :binary, &prc
	end
	def __listen tmode, &prc
		self =~ /:/
		adr, port = $`, $'
		a = adr
		if adr !~ /^(([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]).){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/
			adr = adr.to_ip
		end
		if !adr
			raise Exception.new("cannot resolv address: #{a}")
		end
		sio = nil
		begin
			p adr, port
			sio = (SIOServers[self] ||= SIO.new(TCPServer.new(adr, port.to_i)))
			loop do
				p
				SIO.select sio, :read
				p
				as = sio.io.accept
				esio = SIO.new as, tmode
				SIO.fork do
					p
					begin
						p
						yield esio
						p
					ensure
						esio.close
					end
				end
				p
			end
		ensure
			p $!
			sio.close
			SIOServers.delete self
		end
	end
	def accept &prc
		__listen :binary, &prc
	end
	def accept_T &prc
		__listen :text, &prc
	end
	def url_encode
		CGI.escape self
	end
	def url_decode
		CGI.unescape self
	end
end


class Integer
	def accept &prc
		"0.0.0.0:#{self}".accept &prc
	end
	def accept_T &prc
		"0.0.0.0:#{self}".accept_T &prc
	end
end


def local *args
	yield *args
end


class SIO
	class ExpectException < Exception
	end
	attr :io
	def initialize io, m = :binary
		@io = io
		@mode = m
		@readBuff = ""
		@residue = ""
	end
	def expect arg
		arg = arg.lstrip
		if arg == ""
			return
		end
		loop do
			@readBuff.lstrip!
			break if @readBuff.size > 0
			pre_read
		end
		p @readBuff
		while @readBuff.size < arg.size && @readBuff == arg[0...@readBuff.size] && !@eof
			pre_read
		end
		if @readBuff.size < arg.size
			raise ExpectException.new "expected '#{arg}', but '#{@readBuff}' returned\n"
		else
			p @readBuff[0...arg.size]
			p arg
			p @readBuff[0...arg.size] != arg
			if @readBuff[0...arg.size] != arg
				raise ExpectException.new "expected '#{arg}', but '#{@readBuff}' returned\n"
			end
			@readBuff = @readBuff[arg.size ... @readBuff.size]
			p @readBuff
			return arg
		end
	end
	def expectln arg = nil
		if arg
			expect arg + "\n"
		else
			loop do
				if @readBuff.size == 0
					if !@eof
						pre_read
					else
						raise ExpectException.new "expected empty new line but reached eof\n"
					end
				end
				if @eof
					if @readBuff !~ /^[\t\f\r ]*\n/
						if @readBuff.size == 0
							raise ExpectException.new "expected empty new line but reached eof\n"
						else
							raise ExpectException.new "expected empty new line but read '#{@readBuff}'\n"
						end
					end
					@readBuff = $'
					while @readBuff =~ /^[\t\f\r ]*\n/
						@readBuff = $'
					end
					return
				else
					while @readBuff =~ /^[\t\f\r ]+/
						@readBuff = $'
						if @readBuff.size == 0
							pre_read
						end
					end
					if @eof && @readBuff == ""
						raise ExpectException.new "expected empty new line but reached eof\n"
					end
					if @readBuff[0] != "\n"
						raise ExpectException.new "expected empty new line but read '#{@readBuff}'\n"
					end
					@readBuff = @readBuff[1...@readBuff.size]
					loop do
						while @readBuff =~ /^[\t\f\r ]+/
							if $'.size > 0
								break
							elsif @eof # $'.size == 0
								return
							end
							pre_read
						end
						if @readBuff[0] == "\n"
							@readBuff = @readBuff[1...@readBuff.size]
							next
						end
						return
					end
				end
			end
		end
	end
	def readline
		idx = nil
		res = @readBuff
		@readBuff = ""
		while !(idx = res.index "\n") && !@eof
			pre_read
			res += @readBuff
			@readBuff = ""
		end
		p idx
		if idx
			ret = res[0..idx]
			@readBuff = res[idx + 1 ... res.size]
		else
			ret = res
		end
		ret
	end
	def read_each_line
		p
		loop do
			p
			ret = readline
			if ret != ""
				yield ret
			end
			if @eof && (!@readBuff || @readBuff == "")
				return
			end
		end
	end
	def setmode_B
		if block_given?
			tmp = @mode
			begin
				@mode = "B"
				yield
			ensure
				@mode = tmp
			end
		else
			@mode = "B"
		end
	end
	def read
		ret = ""
		while !@eof
			pre_read
			ret += @readBuff
			@readBuff = ""
		end
		ret
	end
	def unwind s
		@readBuff = s + @readBuff
	end
	def select_write
		self.class.select self, :write
	end
	def select_read
		return if @eof
		p
		self.class.select self, :read
		p
		begin
			p @io
			@readBuff += @io.readpartial 0x3fffffff
			p @readBuff
		rescue EOFError
			p
			@eof = true
		end
		p
	end
	def write arg
		if @mode == :text
			arg = arg.gsub "\n", "\r\n"
		end
		select_write
		p arg
		return @io.write arg
	end
	def writeln arg
		write arg + "\n"
	end
	def pre_read
		loop do
			if @readBuff.size > 0
				break
			end
			@readBuff += @residue
			p
			select_read
			p @readBuff
			if @mode == :text
				@readBuff.gsub! "\r\n", "\n"
				if @mode == :text && @readBuff[-1] == "\r"
					@readBuff.chop!
					@residue = "\r"
				end
			end
			if @readBuff != "" || @eof
				break
			end
		end
	end
	def close
		@io.close if !@io.closed?
	end

	
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
	
	def self.fork *modes, &prc # mode : true, execute block firstly
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
		fProc = Proc.new do
			begin
				p :yellow
				prc.call
				p :cyan
			rescue SIO::SIOTerminate
				p :red
			rescue Exception => ex
				p :blue
				p ex
				ex.instance_eval {
					::STDERR.write "#{backtrace[0]}:#{ex} (#{self.class})".ln
					backtrace[1..-1].each do |e|
						::STDERR.write("   " + e.ln)
					end
				}
				p
				@aborted = true
				abort
			end
			SIO.sid.delete
			p :blue
			doSelect #never retrun
		end
		ret = SIOProc.new.set_params fProc, first ? :start : :pass, auto_cleanup
		cc = callcc do |cont|
			cont
		end
		p cc
		if cc.is_a? Continuation
			SIO.sid.set_params cc, first ? :pass : :start
			p SIO.sid
			doSelect
		end
		p ret
		ret
	end
	class SIOTerminate < Exception
	end
	def self.select_it *args
		cc = callcc do |cont|
			cont
		end
		p cc
		case cc
		when Continuation
			sid.set_params cc, *args
			doSelect
		when :terminate
			p args
			raise SIOTerminate.new
			p
		end
		cc
	end
	def self.select sio, mode, timeout = nil
		select_it mode, sio, timeout
	end
	def self.pass
		select_it :pass
	end
	def self.sleep t = :stop
		p :purple
		select_it t
		p :purple
	end
	def self.stopBy token, timeout = :stop
		res = select_it token, timeout
		if res == :start
			:timeout
		else
			token
		end
	end
	def self.awakeBy token
		SIOProc::List.each do |prc|
			if prc.token == token
				prc.set_params :start
			end
		end
		select_it :start
	end
	def self.timer t
		loop do
			yield
			sleep t
		end
	end
	def self.doSelect
		wios = []
		rios = []
		active_procs = []
		hasTimer = false
		SIOProc::List.each do |prc|
			if prc.timeout
				hasTimer = true
				break
			end
		end
		now = Time.now if hasTimer
		tmout, passProc = nil
		tmoutList = []
		wio2SIOPrc = Hash.new{|h, k| h[k] = []}
		rio2SIOPrc = Hash.new{|h, k| h[k] = []}
		SIOProc::List.each do |prc|
			p prc.selected?, prc.mode, prc.preceeded
			next if prc.preceeded
			case prc.selected? || prc.mode
			when :read, :write
				if prc.mode == :read
					rio2SIOPrc[prc.io].push prc
					rios.push prc.io
				else # :write
					wio2SIOPrc[prc.io].push prc
					wios.push prc.io
				end
				if prc.timeout
					if !tmout || (tmout != 0 and tmout > prc.timeout - now and tmoutList.clear)
						tmout = prc.timeout - now
						tmout = 0 if tmout < 0
					end 
				end
			when :timer
				if !tmout
					tmout = prc.timeout - now
					tmout = 0 if tmout < 0
					tmoutList.push prc
				elsif tmout == 0 && prc.timeout - now <= 0
					tmoutList.push prc
				elsif tmout == prc.timeout - now
					tmoutList.push prc
				elsif tmout > prc.timeout - now
					tmout = prc.timeout - now
					tmout = 0 if tmout < 0
					tmoutList.clear
					tmoutList.push prc
				end
			when :stop
				# do nothing
			when :terminate, :start, true
				if !tmout
					tmout = 0
					tmoutList.push prc
				elsif tmout == 0
					tmoutList.push prc
				else
					tmout = 0
					tmoutList.clear
					tmoutList.push prc
				end
			when :pass
				passProc = prc
				prc.set_params :start
			else # token
				# do nothing
			end
		end
		p tmout
		p [rios, wios, tmoutList]
		if rios.size + wios.size + tmoutList.size == 0
			p
			if passProc
				p passProc
				tmoutList.push passProc
			else
				p
				raise Exception.new("no selectable SIOProc")
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
			[[rios, srios, rio2SIOPrc], [wios, swios, wio2SIOPrc]].each do |ios, sios, io2SIOPrc|
				ios.each do |io|
					e = io2SIOPrc[io].shuffle[0]
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
		current_proc = selectedList.shuffle[0]
		current_proc.reset_selected if current_proc.selected?
		p current_proc
		current_proc.continue
	end
	class SIOProc
		attr_reader :mode, :sio, :timeout, :token, :preceeded
		List = []
		def initialize
			List.push self
			@mutexStack = []
			@lockStat = []
			@mutexList = Hash.new{|h, k| h[k] = 0}
			@preceeded = false
		end
		def delete
			List.delete self
		end
		def auto_cleanup?
			@auto_cleanup
		end
		def io
			if sio.is_a? SIO
				sio.io
			else
				sio
			end
		end
		def set_params *args
			@mode, @timeout, @sio, @token, @selected = nil
			args.each do |e|
				case e
				when Continuation, Proc
					@cont = e
				when :auto_cleanup
					p
					@auto_cleanup = true
				when Symbol
					@mode = e
				when Time
					@timeout = e
				when Numeric
					@timeout = Time.now + e
				when SIO
					@sio = e
				when nil
				else
					@token = e
				end
			end
			@timeout and @mode ||= :timer
			self
		end
		class SIOTerminate < Exception
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
		def awake_at t = 0
			set_params t
		end
		def continue arg = nil
			@mutexStack.each do |e|
				if e.has_semi_lock_sid self
					e.lock self
				end
			end
			m = arg || @mode
			cc = @cont
			@cont, @mode, @timeout, @sio, @token = nil
			SIO.set_sid self
			cc.call m
		end
		def terminate
			if SIO.sid == self
				raise SIOTerminate.new
			end
			set_params :terminate
			SIO.select_it :pass
		end
		def awake
			set_params :start
			SIO.select_it :pass
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
					mutex.set_semi_lock_sid self
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
	end
	class Mutex
		def initialize
			@stopped = {}
			@semi_lock_sids = Hash.new{|h, k| h[k] = 0}
			@waiting_sids = Hash.new
		end
		def lock sid
			while @sid && @sid != sid
				@waiting_sids[sid] = true
				SIO.sleep
			end
			@sid = sid
			@semi_lock_sids.keys.each do |e|
				if e != sid
					e.set_preceeded
				end
			end
			@sid.reset_preceeded
		end
		def unlock sid
			if @sid == sid
				@semi_lock_sids.keys.each do |e|
					if e != self
						e.reset_preceeded
					end
				end
				@waiting_sids.each do |e|
					e.set_awake
				end
				@sid = nil
			end
		end
		def set_semi_lock_sid sid
			@semi_lock_sids[sid] += 1
		end
		def reset_semi_lock_sid sid
			if @semi_lock_sids.key? sid
				tmp = (@semi_lock_sids[sid] -= 1)
				if tmp <= 0
					@semi_lock_sids.delete sid
				end
			end
		end
		def has_semi_lock_sid sid
			@semi_lock_sids.key? sid
		end
		def synchronize mode = :normal, &prc
			SIO.sid.mutexSync self, mode, &prc
		end
	end
	STDIN = SIO.new ::STDIN
	STDOUT = SIO.new ::STDOUT
	STDERR = SIO.new ::STDOUT
	def tmode= m
		@mode = m
	end
	def tmode
		@mode
	end
	def self.set_sid arg
		@sid = arg
	end
	def self.sid
		@sid
	end
	self.set_sid SIOProc.new
	
	at_exit do
		p :cyan, $!
		if $! && !$!.is_a?(SystemExit)
			$!.instance_eval {
				STDERR.write "#{backtrace[0]}:#{$!} (#{self.class})".ln
				backtrace[1..-1].each do |e|
					STDERR.write "   " + e.ln
				end
			}
			@aborted = true
			abort
		end
		p SIOProc::List.size
		toTerm = []
		SIOProc::List.each do |prc|
			if prc.auto_cleanup?
				toTerm.push prc
			end
		end
		p toTerm
		p SIOProc::List.size
		toTerm.each &:terminate
		p SIOProc::List.size
		if !@aborted && SIOProc::List.size > 1
			p SIOProc::List
			raise Exception.new("#{SIOProc::List.size - 1} SIO Fork procedure(s) not cleand")
		end
		p
	end
end


class String
	def strip_indent
		mn = 1000000
		last = nil
		each_line do |ln|
			break if ln[-1] != "\n" and last = ln
			ln.chomp =~ /^\s*/
			next if $'.size == 0
			if $&.size < mn
				mn = $&.size
			end
		end
		res = ""
		each_line do |ln|
			break if ln[-1] != "\n"
			res += ln[mn..-1]  if ln[mn..-1]
		end
		if last
			if last.size <= mn
				res += last.lstrip
			else
				res += last[mn..-1]
			end
		end
		replace(res)
		self
	end
end


class SIOResolver
	Sock = SIO.new UDPSocket.open, :read
	begin
		Sock.io.bind("0.0.0.0", rand(1024..65535))
	rescue => Errno::EADDRINUSE
		retry
	end
	resolvers = []
	"/etc/resolv.conf".read_each_line do |ln|
		if ln.strip =~ /nameserver\s*/ && $' =~ IPv4Regexp
			resolvers.push $&
		end
	end
	Resolvers = resolvers
	MaxRetrial = 5
	EachResolvTimeout = 0.2
	ResolvTimeout = 1.01

	def self.check_init
		if !@initialized
			@initialized = true
			SIO.fork :auto_cleanup do
				p
				loop do
					p
					SIO.select Sock, :read
					p
					pkt = Sock.io.recvfrom(1024)
					parsed = Net::DNS::Packet::parse(pkt)
					name, ip, ttl = nil
					parsed.question.each do |rr|
						p rr.qType.to_s
						p rr.qType.to_s.class
						if rr.qType.to_s == "A"
							name = rr.qName
							if name[-1..-1] == "."
								name.chop!
							end
							break
						end
					end
					parsed.answer.each do |rr|
						if rr.type == "A"
							ip, ttl = rr.address.to_s, rr.ttl
							break
						end
					end
					if ip and name 
						p [name, ip, ttl]
						Status[name].setResult ip, ttl
						p
						SIO.awakeBy [self, name]
						p
					end
				end
			end
		end
	end

	p
	class Status
		attr_reader :expiry, :ip
		def self.[] name
			@list ||= Hash.new{|h, k| h[k] = Status.new(k)}
			@list[name]
		end
		def initialize name
			@name = name
			@expiry = Time.at(0)
		end 
		def resolve
			p
			if @resolving
				p
				@retrialLeft = MaxRetrial
				return
			end
			p
			@resolving = true
			p
			@retrialLeft = MaxRetrial
			p
			SIO.fork do
				p
				begin
					p
					pkt = Net::DNS::Packet.new @name
					p
					begin
						p
						@retrialLeft -= 1
						p
						Sock.io.send(pkt.data, 0, Resolvers[rand(0...Resolvers.size)], 53)
						p
						if !SIO.stopBy [self, @name], EachResolvTimeout
							p
							redo if @retrialLeft > 0
						end
						p
					end
				ensure
					@resolving = false
				end
			end
			p
		end
		def setResult ip, ttl
			@ip = ip
			@expiry = Time.now + ttl
		end
	end

	def self.resolv name
		check_init
		stat = Status[name]
		if stat.expiry > Time.now
			return stat.ip
		end
		p
		stat.resolve
		p
		SIO.stopBy [self, name], ResolvTimeout
		p stat.ip
		return stat.ip
	end

	
end



