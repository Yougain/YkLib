#!/usr/bin/env ruby


require 'Yk/__minmax__'
require 'Yk/proclist'
require 'Yk/path_aux'
require 'Yk/misc_tz'
require 'Yk/syscommand'
require 'Yk/io_aux'
require 'thread'


Process.set_kill_with_children

require 'Yk/__hook__'


class ResultObj
	def error?
		@isError
	end
	def error
		@isError ? @obj : nil
	end
	def result
		!@isError ? @obj : nil
	end
	def initialize (obj, isError = false)
		@obj = obj
		@isError = isError
	end
end


class RemoteProcedure
	attr_reader :obj, :path, :name
	def initialize (obj, path, name, *args, &bl)
		@obj = obj
		@path = path
		@name = name
		@args = args
		bl && (@has_block = true)
	end
	def has_block?
		@has_block
	end
	def remote?
		@path != nil
	end
	def call (manager)
		result = nil
		if @path != nil && @path.strip != ""
			newPathArr = @path.split /:/
			if Etc.getpwuid(Process.euid).name != newPathArr[0]
				remoteManager = RemoteManager.connect(nil, newPathArr[0], *manager.stdPipes)
			end
		end
		if remoteManager
			if !@has_block
				remoteManager.callRemote @obj, newPathArr[1..-1], *@args
			else
				remoteManager.callRemote @obj, newPathArr[1..-1], *@args do |*args|
					yield *args
				end
			end
		else
			begin
				if !@has_block
					res = (@obj || manager).method(@name).call *@args
				else
					res = (@obj || manager).method(@name).call *@args do |*args|
						yield *args
					end
				end
				ResultObj.new(res, false)
			rescue Exception, SignalException => e
				ResultObj.new(e, true)
			end
		end
	end
end


class BlockCaller
	def initialize (*args)
		@args = args
	end
	def execute (&bl)
		bl.call(*@args)
	end
end


class RemoteManager
	def inspect
		[@utilityPipe, @requester, @requestee, @cleaner].inspect
	end
	class RemoteObj
		def initialize (obj, remoteManager, path)
			@obj = obj
			@remoteManager = remoteManager
			@path = path
		end
		def method_missing (name, *args, &bl)
			@remoteManager.callRemote @obj, @path, name, *args, &bl
		end
	end
	@@newMutex = Mutex.new
	@@managers = []
	def initialize (remoteHost, mode, *pidOrPipes)
		@@newMutex.synchronize do
			@mutex = Mutex.new
			@mutexId = Mutex.new
			@cMutex = Mutex.new
			@channels = Hash.new
			@threads = []
			@fps = []
			@closeProcs = []
			@idLast = -1
			@started = false
			case mode
			when :client
				startClient(remoteHost, *pidOrPipes)
			when :server
				startServer(*pidOrPipes)
			else
				startSecondServer(remoteHost, mode, *pidOrPipes)
			end
			at_exit do
				close
			end
			@@managers.push self
		end
	end
	def join
		@threads.each do |e|
			e.join
		end
		@closed = true
	end
	def send (id, buff)
		header = [id, buff.size].pack("i*")
		@mutex.synchronize do
			@ioAfterEncode.write header
			@ioAfterEncode.write buff
			@ioAfterEncode.flush
		end
	end
	def checkId
		@mode == :client ? offset = 35576 * 2 : offset = 35576
		id = nil
		@mutexId.synchronize do
			if @idLast >= 35576
				raise ArguemntError.new("two big id (#{id ? id : @@idLast + 1}) specified.")
			end
			id = (@idLast += 1) + offset
		end
		id
	end
	def setEncoder (io)
		@ioAfterEncode = io
	end
	def setDecoder (io)
		@decoderIO = io
		@readThread = Thread.new do
			begin
				cid = nil
				buff = ""
				while true
					begin
						if (tmp = io.read(8)) == nil
							break
						end
						cid, sz = tmp.unpack("i*")
						io.read(sz, buff)
					rescue EOFError
						break
					end
					if @channels[cid]
						@channels[cid].write buff
					end
				end
			rescue EOFError
			rescue IOError => e
				raise if e.to_s !~ /stream closed/
			end
		end
	end
	def closeDecoder
		@decoderIO.close
	end
	def ioproxy (*args)
		if args.size == 2
			idOrIo, mode = args
		else
			idOrIo, mode = args[0]
		end
		if !(ipxr = @channels[idOrIo])
			ipxr = @channels[idOrIo] = IOProxy.new(self, idOrIo, mode)
			if idOrIo.is_a? IO
				@channels[ipxr.id] = ipxr
			else # idOrIo.is_a? Integer
				@channels[ipxr.io] = ipxr
			end
		end
		ipxr
	end

	def sendClose (id, oprt)
		@cMutex.synchronize do
			@cleaner.write_obj [id, oprt]
		end
	end

	def remove (id, io)
		@channels.delete id
		@channels.delete(io)
	end

	class AlreadyConnected < Exception
		def initialize (obj, msg)
			super msg
			@obj = obj
		end
	end

	@@canonRemoteNames = Hash.new
	def @@canonRemoteNames.insert (k, v)
		if k && !@@canonRemoteNames.key?(k)
			@@canonRemoteNames[k] = v
		else
			raise AlreadyConnected.new(@@canonRemoteNames[k], "#{v} is already used")
		end
	end

	def addThread (t)
		@threads.push t
	end

	def startClient (remoteHost, *stdPipes)
		_in, _out, _err = stdPipes
		@mode = :client
		@stdPipes = stdPipes
		magic = rand(100000000).to_s
		f0, f1, f2 = [$0, "--spipe-magic=#{magic}", "--spipe-base=#{@@base}",  "--spipe-remote=#{@@local}"].popen3_at(remoteHost)
		echoOff = nil
		orgMode = nil
		controlStarted = false
		tb = nil
		begin
			if _in.tty?
				orgMode = _in.stty_mode
				if orgMode != (echoOff = orgMode & ~Termios::ECHO)
					_in.stty_mode = echoOff
				end
			end
			ta = _in.transfer_to(f0)
			tb = f2.transfer_to(_err)
			f1.transfer_to(_out, magic) do
				ta.terminate
				ta.join
				f0.flush
				f0.tty? && f0.set_raw
				f0.write_obj magic
				f0.flush
				controlStarted = true
				tb.terminate
			end
			tb.join
		ensure
			if echoOff
				_in.stty_mode = orgMode
			end
		end
		if !controlStarted
			raise Exception.new("failed to connect to #{remoteHost}")
		end
		setEncoder(f0)
		f1.tty? && f1.set_raw
		addThread setDecoder(f1)
		@utilityPipe = ioproxy(0, "r+")
		@requester = ioproxy(1, "r+")
		@requestee = ioproxy(2, "r+")
		@cleaner = ioproxy(3, "r+")
		@canonRemoteName = @utilityPipe.read_obj
		begin
			@@canonRemoteNames.insert @canonRemoteName, self
		rescue AlreadyConnected => e
			@utilityPipe.write_obj nil
			raise
		end
		@utilityPipe.write_obj @@local
		addThread answerLoop
		addThread startCleaner
		callRemote(nil, nil, :setStdPipes, _in, _out, _err)
	end
	
	def setStdPipes (_in, _out, _err)
		if @isFirstServer
			STDIN.reopen _in
			STDOUT.reopen _out
			recoverErrBuff _err
		end
		@stdPipes = [_in, _out, _err]
	end

	class IOLog < Array
		def initialize
			super
			@r, @w = IO.pipe
			@r.nonblock = true
			@w.nonblock = true
			@thread = Thread.new do
				cmd = ["/usr/bin/multilog", "t", "#{ENV['HOME']}/.spipe/log/#{$0.basename}".check_dir]
				cmd.condSQuote.open "pw" do |fw|
					begin
						while true
							push tmp = @r.readpartial(1024)
							fw.write tmp
							fw.flush
						end
					rescue EOFError => e
					end
				end
			end
		end
		def io
			@w
		end
		def terminate
			@thread.terminate
		end
	end

	def setErrLog
		@errBuff = IOLog.new
		STDERR.reopen @errBuff.io
	end

	def recoverErrBuff (newIO)
		#@errBuff.terminate
		#newIO.write *@errBuff
		#STDERR.reopen newIO
	end
	
	def startServer (magic, _in = STDIN.dup, _out = STDOUT.dup, remote = @@remote, isFirstServer = true)
		@mode = :server
		@isFirstServer = isFirstServer
		_in.nonblock = true
		_out.nonblock = true
		setErrLog
		_out.write magic
		_out.flush
		_out.tty? && _out.set_raw
		_in.tty? && _in.set_raw
		if _in.read_obj != magic
			raise Exception.new("magic string not detected")
		end
		addThread setDecoder(_in)
		setEncoder(_out)
		@utilityPipe = ioproxy(0, "r+")
		@requestee = ioproxy(1, "r+")
		@requester = ioproxy(2, "r+")
		@cleaner = ioproxy(3, "r+")
		begin
			@@canonRemoteNames.insert remote, self
		rescue AlreadyConnected => e
			@utilityPipe.write_obj nil
			close
			raise
		end
		@utilityPipe.write_obj @@local
		if !@utilityPipe.read_obj
			@@canonRemoteNames.delete remote
			close
			raise AlreadyConnected.new(nil, "peer saids already connected")
		end
		addThread answerLoop
		addThread startCleaner
	end
	
	def on_close (&bl)
		@closeProcs.push bl
	end
	
	def startSecondServer (remote, cid, pid, magic)
		inpipe = self.class.infoDir / "inpipe.#{cid}"
		outpipe = self.class.infoDir / "outpipe.#{cid}"
		delpipe = self.class.infoDir / "delpipe.#{cid}"
		@fps.push _in = inpipe.open("nr")
		@fps.push _out = outpipe.open("nw")
		@fps.push _del = delpipe.open("nw")
		on_close do
			if (tmp = ProcList.pid(pid)) && tmp.prog == $0 && delpipe.exist?
				_del.write_obj nil
			end
		end
		begin
			startServer(magic, _in, _out, remote, false)
		rescue
			_del.write_obj nil
			raise
		end
	end

	def close (byRemote = false)
		if !@closed
			@@newMutex.synchronize do
				@closed = true
				@closeProcs.each do |e|
					e.call
				end
				@channels.values.uniq.each do |e|
					if e.mode == :proxy
						e.close
					end
				end
				@utilityPipe.close
				@requester.close
				@requestee.close
				byRemote or @cleaner.write_obj "close_all"
				@cleaner.close
				closeDecoder
				@fps.each do |fp|
					fp.closed? || fp.close
				end
				@threads.each do |t|
					t.join if t != Thread.current
				end
			end
		end
	end

	def startCleaner
		Thread.new do
			begin
				@cleaner.each_obj do |obj|
					if obj == "close_all"
						close(true)
					else
						@channels[obj[0]].closeBySent(obj[1])
					end
				end
			rescue EOFError
			rescue IOError => e
				raise if e.to_s !~ /stream closed/
			end
		end
	end

	def callRemote (obj, path, funcLabel, *args, &bl)
		@requester.write_obj RemoteProcedure.new(obj, path, funcLabel, *args, &bl)
		ret = nil
		begin
			while answer = @requester.read_obj
				if answer.is_a? BlockCaller
					if bl
						@requester.write_obj answer.execute(&bl)
					else
						@requester.write_obj nil
					end
				elsif answer.is_a? ResultObj
					if path == nil
						if answer.error?
							$! = answer.error
							raise
						else
							ret = answer.result
						end
						break
					else
						ret = answer.result
						break
					end
				else
					raise Exception.new("unknown error")
				end
			end
		rescue EOFError
		end
		ret
	end
	
	def answerLoop
		Thread.new do
			begin
				while true
					procedure = @requestee.read_obj
					result = nil
					if procedure.has_block?
						result = procedure.call self do |*args|
							@requestee.write_obj BlockCaller.new(*args)
							@requestee.read_obj
						end
					else
						result = procedure.call self
					end
					@requestee.write_obj result
				end
			rescue EOFError
			rescue IOError => e
				raise if e.to_s !~ /stream closed/
			end
		end
	end
	@@remoteHosts = Hash.new
	def self.connect (tag, remoteHost, *pipes)
		(pipes.size .. 2).each do |i|
			pipes.push [STDIN, STDOUT, STDERR][i]
		end
		arr = remoteHost.split(/:/)
		remoteManager = nil
		begin
			remoteManager = @@remoteHosts[arr[0]] ||= new(arr[0], :client, *pipes)
		rescue AlreadyConnected => e
			remoteManager = e.remoteManager
		end
		if tag
			RemoteObj.__defun__ tag do |obj|
				 RemoteObj.new(obj, remoteManager, arr[1..-1].join)
			end
			Object.class_eval %{
				def #{tag}
					RemoteObj.#{tag} self
				end
			}
		end
		remoteManager
	end
	def self.base
		@@base
	end
	HOME = Etc.getpwuid(Process.euid).dir
	def self.infoDir
		HOME / ".spipe" / $0.basename + "--" + @@base
	end
	def self.checkRemoteEntry
		lock = infoDir / "lock--#{@@remote}"
	end
	def self.startSecondTransferAgent (magic)
		cid = nil
		(infoDir / "cpipe.lock").lock_ex do
			rem_cpipe = infoDir / "cpipe.rem"
			cid_cpipe = infoDir / "cpipe.cid"
			rem_cpipe.open "nw" do |f|
				f.write_obj [@@remote, $$.to_i, magic]
				f.flush
			end
			cid_cpipe.open "nr" do |f|
				cid = f.read_obj
			end
		end
		wpipe = infoDir / "inpipe.#{cid}"
		rpipe = infoDir / "outpipe.#{cid}"
		dpipe = infoDir / "delpipe.#{cid}"
		cleanFiles = Proc.new do
			wpipe.rm_f
			rpipe.rm_f
			dpipe.rm_f
		end
		at_exit do
			cleanFiles.call
		end
		wpipe.fifo? || wpipe.mkfifo
		rpipe.fifo? || rpipe.mkfifo
		dpipe.fifo? || dpipe.mkfifo
		t0 = Thread.new do
			dpipe.read
			cleanFiles.call
			exit 0
		end
		STDIN.nonblock = true
		t = Thread.new do
			buff = ""
			wpipe.open "nw" do |fw|
				while true
					STDIN.readpartial 1024, buff
					fw.write buff
					fw.flush
				end
			end
		end
		buff2
		STDOUT.nonblock = true
		rpipe.open "n" do |fr|
			while true
				fr.readpartial 1024, buff2
				STDOUT.write buff2
				STDOUT.flush
			end
		end
		t.join
	end
	
	def self.start
		(infoDir / "lock").try_lock_ex
	end
	
	@@cid = 0
	def self.startSecondManager
		rem_cpipe = infoDir / "cpipe.rem"
		rem_cpipe.fifo? || rem_cpipe.mkfifo
		cid_cpipe = infoDir / "cpipe.cid"
		cid_cpipe.fifo? || cid_cpipe.mkfifo
		t = Thread.new do
			rem_cpipe.open "n" do |fr|
				fr.each_obj do |rem, agentPid, magic|
					@@cid += 1
					cid_cpipe.open "n" do |fw|
						fw.write_obj @@cid
					end
					new(rem, @@cid, agentPid, magic)
				end
			end
		end
	end
end


class IO
	def _dump (limit)
		proxy = IOProxy.remoteManagerToDump.ioproxy(self)
		str = Marshal.dump([proxy.id, proxy.fmode], limit)
		str
	end
	def self._load (stream)
		id, fmode = Marshal.load(stream)
		proxy = IOProxy.remoteManagerToLoad.ioproxy(id, fmode.reverse)
		proxy.io
	end
end


class IOProxy
	attr_reader :id, :fmode, :toRemote, :mode
	def io
		@io || @toRemote
	end
	def check_remove
		if @mode != :life
			@toRemote.closed? || @toRemote.close
		end
		@remoteManager.remove(@id, @idf)
	end
	def write (buff)
		checkWriteThread
		@wMutex.synchronize do
			@residue += buff
			if @residue.size > 0
				@wCv.signal
			end
		end
	end
	def checkWriteThread
		if !@wThread
			@wMutex = Mutex.new
			@wCv = ConditionVariable.new
			Thread.new do
				@wThread = Thread.current
				@wMutex.synchronize do
					while true
						while @residue.size == 0
							@wCv.wait(@wMutex)
						end
						wsz = 0
						begin
							wsz = @toRemote.write_nonblock @residue
						rescue Errno::EAGAIN => e
							Thread.pass
						end
						@residue.slice!(0...wsz)
					end
				end
			end
		end
	end
	def startEncoder
		@thread = Thread.new do
			begin
				buff = ""
				while true
					@toRemote.readpartial(1024, buff)
					@remoteManager.send @id, buff
				end
			rescue EOFError
			rescue Errno::EIO
				retry
			rescue IOError => e
				raise if e.to_s !~ /stream closed/
			end
		end
	end
	public
	def initialize (remoteManager, idOrIO, fmode = nil)
		@remoteManager = remoteManager
		@mutex = Mutex.new
		@residue = ""
		@closeSent = Hash.new
		if idOrIO.is_a? Integer
			@id = idOrIO
			@mode = @id > 35575 ? :proxy : :system
			@io, @toRemote = IO.pipe(fmode)
			@io.nonblock = true
			@toRemote.nonblock = true
			@fmode = fmode.to_fmode
			if @mode == :system
				@io.__hook__ :write_obj do |org|
					IOProxy.__context_var__ :remoteManagerToDump, @remoteManager do
						org.call
					end
				end
				@io.__hook__ :read_obj do |org|
					IOProxy.__context_var__ :remoteManagerToLoad, @remoteManager do
						org.call
					end
				end
			end
		else
			@mode = :life
			@id = @remoteManager.checkId
			@idf = idOrIO
			@toRemote = idOrIO
			@toRemote.nonblock = true
			@toRemote.__defun__ :proxy, self
			@fmode = @toRemote.fmode.reverse
		end
		if @mode != :system
			[:close, :close_write, :close_read].each do |label|
				oprt = IO::CloseOperation.new(label)
				io.__hook__ label, oprt do |org, op|
					!@closeSent[label] && @remoteManager.sendClose(@id, op)
					org.call
					@mode == :proxy && @toRemote.method(op.reverse.to_label).call
					check_remove
				end
			end
		end
		if @toRemote.readable?
			startEncoder
		end
	end
	def write_obj (obj)
		io.write_obj obj
	end
	def read_obj
		io.read_obj
	end
	def each_obj (&bl)
		io.each_obj &bl
	end
	def close
		@mutex.synchronize do
			io.closed? || io.close
		end
	end
	def closeBySent (oprt)
		label = oprt.to_label
		@mutex.synchronize do
			if !@closeSent[label]
				@closeSent[label] = true
				io.method(label).call
			end
		end
	end
end


class RemoteManager
	@@local = ENV['USER'] + "@" + `hostname`.chomp
	@@base = nil
	ARGV.each_index do |i|
		while i < ARGV.size && ARGV[i] =~ /^\-\-spipe\-base\=(.*)$/
			@@base = $1
			ARGV.slice!(i)
		end
	end
	@@remote = nil
	ARGV.each_index do |i|
		while i < ARGV.size && ARGV[i] =~ /^\-\-spipe\-remote\=(.*)$/
			@@remote = $1
			ARGV.slice!(i)
		end
	end
	magic = nil
	ARGV.each_index do |i|
		while i < ARGV.size && ARGV[i] =~ /^\-\-spipe\-magic\=(.*)$/
			magic = $1
			ARGV.slice!(i)
		end
	end
	if !@@base
		@@base = ENV['USER'] + "@" + `hostname`.chomp
		infoDir.mkdir_p
		if @@base == "localhost.localdomain"
			raise Exception.new("cannot use #{@@base}; please set a unique name to the host")
		end
		if !tmp = start
			raise Exception.new("second instance is not allowed")
		else
			t = startSecondManager
			at_exit do
				t.terminate
			end
		end
	else
		infoDir.mkdir_p
		if !start
			startSecondTransferAgent magic
			exit 0
		else
			t = startSecondManager
			at_exit do
				t.terminate
			end
			m = new(@@remote, :server, magic)
			m.join
			@@managers.each do |mg|
				mg.close
			end
			exit 0
		end
	end
end


#def main
#	fw, fr, fe = IOProxy.createPipes "mailip -g"
#	fw.write "hello!"
#	println fr.read # "good bye!"
#end

#	IOProxy.callRemote :system, "mailip -g" do |fw, fr, fe|
#		
#	end


#  fw = remote2["/var/tmp/file"].open "w"
#  remote1["/var/tmp/file"].open "r" do |fr|
#      fr.each_line do |ln|
#            fw.write ln
#      end
#  end

