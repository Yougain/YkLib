require 'Yk/path_aux'
require 'net/smtp'
require 'base64'
require 'uri'
require 'net/dns'


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
	def to_ip
		SIOResolver.resolv self
	end
	def __open tmode, &prc
		self =~ /:/
		adr, port = $`, $'
		if adr !~ /^(([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]).){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/
			p
			adr = adr.to_ip
			p
		end
		s = TCPSocket.new(adr, port.to_i)
		s.set_sio tmode
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
	def __listen tmode
		self =~ /:/
		adr, port = $`, $'
		if adr !~ /^(([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]).){3}([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/
			adr = adr.to_ip
		end
		sio = nil
		begin
			sio = (SIOServers[self] ||= SIO.new(TCPServer.new(adr, port.to_i)))
			loop do
				SIO.select sio, :read
				sio.io.accept do |s|
					s.set_sio tmode
					SIO.fork do
						yield s.sio
					end
				end
			end
		ensure
			sio.close
			SIOServers.delete self
		end
	end
	def listen
		__listen :binary
	end
	def listen_T
		__listen :text
	end
	def url_encode
		URI.url_escape self
	end
	def url_decode
		URI.url_unescape self
	end
end


class Integer
	def listen &prc
		"0.0.0.0:#{self}".listen &prc
	end
end


def local *args
	yield *args
end


class SIO
	class ExpectException < Exception
	end
	attr :io
	def initialize io, m
		@io = io
		@mode = m
		@readBuff = ""
		@residue = ""
	end
	def expect arg
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
			raise ExceptException.new "expected '#{arg}', but '#{@readBuff}' returned\n"
		else
			p @readBuff
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
						raise ExceptException.new "expected empty new line but reached eof\n"
					end
				end
				if @eof
					if @readBuff !~ /^[\t\f\r ]*\n/
						if @readBuff.size == 0
							raise ExceptException.new "expected empty new line but reached eof\n"
						else
							raise ExceptException.new "expected empty new line but read '#{@readBuff}'\n"
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
						raise ExceptException.new "expected empty new line but reached eof\n"
					end
					if @readBuff[0] != "\n"
						raise ExceptException.new "expected empty new line but read '#{@readBuff}'\n"
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
	def read
		ret = ""
		while !@eof
			pre_read
			ret += @readBuff
			@readBuff = ""
		end
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
		@io.close
	end
	def self.continue_procs
		@main_cont.call
	end
	def self.exit
		if @proc_to_select.size > 0
			@select_one.call
		else
			Kernel.exit status
		end
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
	
	
	class ForkObj
		def awake_at t
			SIO.proc_to_select.each do |prc|
				if prc.forkObj == self && prc.sio._?.is_a?(Time).__it > t
					prc.set_sio t
					break
				end
			end
		end
		def exit
			
		end
	end
	def self.forkObj
		@forkObj ||= ForkObj.new
	end
	def self.fork mode = false, &prc # mode : true, execute block firstly
		cc = callcc do |cont|
			cont
		end
		p cc
		if cc.is_a? Continuation
			cc_frk = callcc do |cont|
				cont
			end
		end
		p cc, cc_frk
		case [cc.is_a?(Continuation), cc_frk.is_a?(Continuation)]
		when [true, true]
			cc, cc_frk = cc_frk, cc if mode
			(@proc_to_select ||= []).push SIOProc.new(cc, :pass)
			@proc_to_select.push SIOProc.new(cc_frk, :fork)
			@select_one.call
		when [false, true]
			cc = cc_frk
			begin
				prc.call
			rescue Exception => ex
				ex.instance_eval {
					STDERR.write "#{backtrace[0]}:#{ex} (#{self.class})".ln
					backtrace[1..-1].each do |e|
						STDERR.write "   " + e.ln
					end
				}
				@aborted = true
				abort
			end
			if @proc_to_select.size > 0
				@select_one.call
			else
				raise Exception.new "unknown fork finalization error\n"
			end
		when [true, false]
			cc_frk = cc
			return forkObj
		else
			raise Exception.new "unknown fork finalization error\n"
		end
	end
	def self.pass
		cc = callcc do |cont|
			cont
		end
		if cc.is_a? Continuation
			(@proc_to_select ||= []).push SIOProc.new(cc, :pass)
			@select_one.call
		end
	end
	def self.sleep t = :stop
		cc = callcc do |cont|
			cont
		end
		if cc.is_a? Continuation
			t != :stop and t += Time.now 
			(@proc_to_select ||= []).push SIOProc.new(cc, t)
			@select_one.call
		end
	end
	def self.stopBy token, timeout = :stop
		cc = callcc do |cont|
			cont
		end
		if cc.is_a? Continuation
			(@proc_to_select ||= []).push SIOProc.new(cc, timeout, token)
			@select_one.call
		else
			if cc == :start
				:timeout
			else
				token
			end
		end
	end
	def self.awakeBy token
		cc = callcc do |cont|
			cont
		end
		if cc.is_a? Continuation
			(@proc_to_select ||= []).each do |prc|
				if prc.token == token
					prc.set_sio :start
				end
			end
			(@proc_to_select ||= []).push SIOProc.new(cc, :start)
			@select_one.call
		end
	end
	def self.timer t
		loop do
			yield
			sleep t
		end
	end
	def self.select_one
		p5
		cc = callcc do |cont|
			cont
		end
		if cc.is_a? Continuation
			@select_one = cc
		else
			wios = []
			rios = []
			active_procs = []
			hasTimer = false
			@proc_to_select.each do |prc|
				if prc.timeout
					hasTimer = true
					break
				end
			end
			now = Time.now if hasTimer
			tmout = nil
			tmoutList = []
			wio2SIOPrc = Hash.new{|h, k| h[k] = []}
			rio2SIOPrc = Hash.new{|h, k| h[k] = []}
			p
			@proc_to_select.each do |prc|
				p prc.selected?, prc.mode
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
				when :start, true
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
					prc.set_sio :start
				else # token
					# do nothing
				end
			end
#			p @proc_to_select
			p tmout
			p [rios, wios, tmoutList]
			selectedList, srios, swios = nil
			if !tmout || tmout != 0
				begin
					srios, swios, = IO.select rios, wios, [], tmout
				rescue Errno::EINTR
					retry
				end
				now = nil
				timeouted = (!srios || srios.size == 0) && (!swios || swios.size == 0)
				[[rios, srios, rio2SIOPrc], [wios, swios, wio2SIOPrc]].each do |ios, sios, io2SIOPrc|
					ios.each do |io|
						io2SIOPrc[io].each do |e|
							if (sios && sios.include?(io)) || (e.timeout && e.timeout < (now ||= Time.now))
								e.set_selected
								(selectedList ||= []).push e
							end
						end
					end
				end
			else #tmout = 0
				timeouted = true
			end
			p rios
			p wios
			p selectedList
			p tmoutList
			if timeouted
				(selectedList ||= []).push *tmoutList
			end
			current_proc = selectedList.shuffle[0]
			current_proc.reset_selected if current_proc.selected?
			@proc_to_select.delete current_proc
			@forkObj = current_proc.forkObj
			p current_proc
			current_proc.continue
		end
	end
	def self.select sio, mode, timeout = nil
		prc = SIOProc.new
		if prc.set_cont sio, mode, timeout
			(@proc_to_select ||= []).push prc
			@select_one.call
		end
	end
	class SIOProc
		attr_reader :mode, :sio, :forkObj, :timeout, :token
		def io
			if sio.is_a? SIO
				sio.io
			else
				sio
			end
		end
		def initialize *args
			args.each do |e|
				case e
				when Continuation
					@cont = e
				when :fork
					@mode = :start
					@forkObj = ForkObj.new
				when Symbol
					@mode = e
				when Time
					@timeout = e
				when Numeric
					@timeout = Time.now + e
				else
					@token = e
				end
			end
			@timeout and @mode ||= :timer
			@forkObj ||= SIO.forkObj
		end
		def set_sio t
			if t.is_a? Time
				@mode = :timer
				@timeout = t
			elsif t == :pass
				@mode = :pass
				@sio = nil
			elsif t == :start
				@mode = :start
				@sio = nil
			end
		end
		def set_cont sio, mode, timeout
			@sio = sio
			@mode = mode
			if timeout
				@timeout = timeout.is_a?(Numeric) ? timeout + Time.now : timeout
			end
			cc = callcc do |cont|
				cont
			end
			if cc.is_a? Continuation
				@cont = cc
				true
			else
				false
			end
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
		def continue
			@sio = nil
			mode = @mode
			@mode = nil
			@cont.call mode
		end
	end
	def self.proc_to_select
		@proc_to_select ||= []
	end
	def self._exit
		if @proc_to_select.size > 0
			@select_one.call
		end
	end
	STDIN = ::STDIN.set_sio
	STDOUT = ::STDOUT.set_sio
	STDERR = ::STDOUT.set_sio
	def tmode= m
		@mode = m
	end
	def tmode
		@mode
	end
	self.select_one
	at_exit do
		if $!
			$!.instance_eval {
				STDERR.write "#{backtrace[0]}:#{$!} (#{self.class})".ln
				backtrace[1..-1].each do |e|
					STDERR.write "   " + e.ln
				end
			}
			@aborted = true
			abort
		end		
		if !@aborted && proc_to_select.size > 0
			p
			pass
		end
	end
end


class String
	def strip_indent
		mn = 1000000
		last = nil
		each_line do |ln|
			break if (last = ln)[-1] != "\n"
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
		if last && last.size <= mn
			res += last.lstrip
		else
			res += last[mn..-1]
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

	p
	SIO.fork true do
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

p

