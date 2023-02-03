


module SystemCommand
	require 'tempfile'
	PROG_SSHA = "/usr/bin/ssha"
	PROG_SSH = "/usr/bin/ssh"
	def handleIO (arr, bl)
		if bl
			begin
				ret = bl.call *arr
				t = Process.detach arr[0].pid
				t.join
				ret = !$?.exitstatus ? nil : $?.exitstatus == 0
			ensure
				arr.each do |e|
					e.closed? || e.close
				end
			end
			ret
		else
			arr
		end
	end
	module_function :handleIO
	def popen3_at (remoteHost, *args, &bl)
		cmdArr = nil
		requirePty = true
		toSu = nil
		begin
			toSu = Etc.getpwnam(userEntry = remoteHost)
		rescue ArgumentError
		end
		if toSu != nil
			if userEntry == "root"
				if Process.euid != 0
					if File.executable?(tmp = "/usr/sbin/cansudo") && system(tmp) && $? == 0
						cmdArr = ["sudo"] + args
					else
						cmdArr = ["su", "-c", args.condSQuote]
					end
				else
					cmdArr = args
					requirePty = false
				end
			else
				cmdArr = ["su", remoteHost, "-c", args.condSQuote]
			end
		else
			if PROG_SSHA.executable_file? && remoteHost !~ /\@/
				cmdArr = [PROG_SSHA, "--no-cocot", remoteHost, "-t"] + args
			else
				bin = PROG_SSH
				cmdArr = [PROG_SSH, remoteHost, "-t"] + args
			end
			if Process.euid == 0
				if ENV['SUDO_USER']
					cmdArr = ["su", ENV['SUDO_USER'], "-c", cmdArr.condSQuote]
				elsif ENV['LOGNAME'] != "root"
					cmdArr = ["su", ENV['LOGNAME'], "-c", cmdArr.condSQuote]
				end
			end
		end
		if requirePty
			f0, f1, f2 = pty_spawn3 *cmdArr
		else
			f0, f1, f2 = popen3 *cmdArr
		end
		handleIO [f0, f1, f2], bl
	end
	module_function :popen3_at
	String.class_eval do
		def popen3_at (remoteHost, &bl)
			SystemCommand.popen3_at(remoteHost, self, &bl)
		end
	end
	Array.class_eval do
		def popen3_at (remoteHost, &bl)
			SystemCommand.popen3_at(remoteHost, *self, &bl)
		end
	end
	def self.method_added (name)
		module_function name
		String.class_eval %{
			def #{name} (*args, &bl)
				#{self.name}.#{name} *([self] + args), &bl
			end
		}
		Array.class_eval %{
			def #{name} (&bl)
				#{self.name}.#{name} *self, &bl
			end
		}
	end
	def popen3 (*args, &bl)
		stdinWrite, stdinRead = IO.pipe
		stdoutRead, stdoutWrite = IO.pipe
		stderrRead, stderrWrite = IO.pipe
		[stdinWrite, stdinRead, stdoutRead, stdoutWrite, stderrRead, stderrWrite].each do |e|
			e.nonblock = true
		end
		pid = fork do
			STDIN.reopen stdinRead
			STDOUT.reopen stdoutWrite
			STDERR.reopen stderrWrite
			exec *args
		end
		arr = [stdinWrite, stdoutRead, stderrRead]
		arr.each do |e|
			e.__defun__ :pid, pid
		end
		handleIO arr, bl
	end
	def spawn (*args)
		pid = fork do
			exec *args
		end
		return pid
	end
	require 'pty'
	def pty_spawn3 (*args, &bl)
		stdoutRead, stdoutWrite = IO.pipe
		stderrRead, stderrWrite = IO.pipe
		[stdoutRead, stdoutWrite, stderrRead, stderrWrite].each do |e|
			e.nonblock = true
		end
		fp = nil
		fp, slave = PTY.open
		if !fp
			Exception.new("cannot allocate pseudo tty")
		end
		pid = fork do
			STDIN.reopen(slave)
			STDOUT.reopen stdoutWrite
			STDERR.reopen stderrWrite
			exec *args
		end
		fList = [fp, stdoutRead, stderrRead]
		fList.each do |f|
			f.__defun__ :pid, pid
		end
		handleIO fList, bl
	end
	def psu6 (*args, &bl)
		if Process.euid != 0
			if !STDIN.tty?
				raise Exception.new("cannot su because input is not a tty")
			end
			cmd = [__FILE__, args.condSQuote, tmpFifo3, tmpFifo4, tmpFifo5]
			if File.executable?(tmp = "/usr/sbin/cansudo") && system(tmp) && $? == 0
				cmdArr = ["sudo"] + cmd
			else
				cmdArr = ["su", "-c", cmd.condSQuote]
			end
			tmpFifo3 = Tempfile.mkfifo
			tmpFifo4 = Tempfile.mkfifo
			tmpFifo5 = Tempfile.mkfifo
			f0, f1, f2 = pty_spawn3 *cmdArr
			f3 = tmpFifo3.nb_open "w"
			f4 = tmpFifo4.nb_open "r"
			f5 = tmpFifo5.nb_open "r"
			[f3, f4, f5].each do |e|
				e.__defun__ :pid, f0.pid
			end
			handleIO [f3, f4, f5, f0, f1, f2], bl
		else
			pty_spawn3(*args, &bl)
		end
	end

end


