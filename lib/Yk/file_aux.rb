

require 'pathname'
require 'Yk/__defun__'
require 'Yk/__hook__'
require 'Yk/io_aux'
require 'pty'
require 'Yk/misc_tz'

(class << File; self; end).class_eval do
	alias_method :__org_open_____, :open
	at_exit do
		begin
		#	FileUtils.rm_rf "#{ENV['HOME']}/.tmp/#{File.basename($0)}/instances/#{$$}"
		#	FileUtils.rmdir("#{ENV['HOME']}/.tmp/#{File.basename($0)}/instances") rescue ""
		#	FileUtils.rmdir("#{ENV['HOME']}/.tmp/#{File.basename($0)}") rescue ""
		rescue Exception
		end
	end
	def open (f, mode = "r", perm = nil, **opts)
		tmp_mode = false
		#if f == ""
		#	if !File.exist? "#{ENV['HOME']}/.tmp/#{File.basename($0)}/instances/#{$$}"
		#		File.mkpath "#{ENV['HOME']}/.tmp/#{File.basename($0)}/instances/#{$$}"
		#	end
		#	f.replace("#{ENV['HOME']}/.tmp/#{File.basename($0)}/instances/#{$$}/tmp.#{rand(10000000000).to_s}")
		#	tmp_mode = true
		#	fmode.delete = true
		#end
		res = nil
		fmode = mode.to_fmode
		pid = nil
		handleIO = Proc.new do |h|
			p
			pid && h.__defun__(:pid, pid)
			p
			if block_given?
				p
				begin
			#		p h
					res = yield h
				ensure
					h.closed? || h.close
					if pid
						begin
							Process.waitpid pid
						rescue => e
						end
					end
				end
				if pid
					res = !($? && $?.exitstatus) ? nil : res
				else
					res
				end
			else
				p
				res = h
			end
		end
		fp = nil
		execIt = Proc.new do |cmdLine|
			opts = opts.clone
			uname = opts.delete :user
			euname = opts.delete(:euser) || uname
			runame = opts.delete(:ruser) || uname
			chdir = opts.delete :chdir
			if chdir == :home
				chdir = Etc::User.home uname
			end
			require 'Yk/misc_tz'
			if Etc::EUser.current? euname
				exec *cmdLine, **opts
			elsif Etc::User.root? euname
				require "shellwords"
				if (File.executable?(tmp = "/usr/sbin/cansudo") && system(tmp) && $? == 0 && STDIN.tty?) or "/etc/group".read =~ /\nwheel|sudo:.*\b(#{Regexp.escape Etc.getpwuid(Process.euid).name})\b/
					exec "sudo", *cmdLine, **opts
				else
					exec "su", "-c", Shellwords.join(cmdLine), **opts
				end
			else
				if Process.euid == 0
					Process.euid = Etc::User.id(euname)
					Process.uid = Etc::User.id(runame)
					Dir.chdir chdir if chdir
					exec *cmdLine, **opts
				else
					require "shellwords"
					["su", Etc::User.name(uname),  "-c", Shellwords.join(cmdLine)].__command_tz__2 mode, env, opts
				end
			end
		end
		doProg = Proc.new do |cmdLine|
			if fmode.sys?
				raise ArgumentError.new("cannot use popen with sysopen")
			end
			if !fmode.terminal?
				fp, ff = nil
				if fmode.readable? && fmode.writable?
					raise ArgumentError.new("function not yet implemented")
					#	fr, fout = IO.pipe
					#	pid = fork do
					#		fr.close
					#		fw.close
					#		STDIN.reopen fin
					#		fmode.stdout? && STDOUT.reopen(fout)
					#		fmode.stdout? && STDERR.reopen(fout)
					#		exec *cmdLine
					#	end
					#	fin.close
					#	fout.close
					#	fr.set_write_io fw
					#	fp = fr
				else
					p
					if fmode.encode
						fr, fw = IO.pipe fmode.encode
					else
						fr, fw = IO.pipe
					end
					fcs = [] 
					if fmode.writable?
						fp, ff = fw, fr
						fcs.push STDIN
					else
						fp, ff = fr, fw
						fmode.stdout? && fcs.push(STDOUT)
						fmode.stderr? && fcs.push(STDERR)
					end
					#fr.nonblock = true
					#fw.nonblock = true
					pid = fork do
						fp.close
						fcs.each do |fc|
							fc.reopen ff
						end
						ff.close
						execIt.call cmdLine
					end
					
					ff.close
				end
				handleIO.call fp
			else
				fp = nil
				fq, fp = PTY.open
				if !fp
					raise Exception.new("cannot allocate pseudo tty")
				end
				fp.set_raw
				fq.set_raw
				pid = fork do
					Process.setsid
			#Process.setpgrp
					if fmode.encode && !fmode.encode.empty?
						fqx = IO.reopen fq, "r+:#{fmode.encode}" 
						fq.close
						fq = fqx
					end
					begin
						STDIN.reopen fq
						STDOUT.reopen fq
						STDERR.reopen fq
					rescue
					end
					fq.close
					fp.close
					execIt.call cmdLine
				end
				fq.close
				trap :WINCH do
				end
				handleIO.call fp
			end
		end
		if f.is_a? Array
			doProg.call f
		elsif f.is_a? String
			f = f.clone
			case f
			when "|-"
				f = "-"
				fmode.pmode = :program
				fmode.writable = true
			when "-|"
				f = "-"
				fmode.pmode = :program
				fmode.readable = true
			when "|-|"
				f = "-"
				fmode.pmode = :program
				fmode.readable = true
				fmode.writable = true
			when "-"
				fmode.pmode = :program
			else
				if f =~ /^\|/
					f.sub!(/^\|/, "")
					fmode.writable = true; fmode.pmode = :program
				end
				if f =~ /^\|/
					f.sub!(/^\|/, "")
					fmode.readable = true; fmode.pmode = :program
				end
			end
			if f == "-"
				raise ArgumentError.new("function for '-' is not yet implemented")
			else
				File.pipe?(f) && fmode.pmode = :pipe
				case fmode.pmode
				when :program, :terminal
					doProg.call [f]
				else
					writeFile = nil
					getFp = Proc.new do |m|
						if fmode.pmode == :pipe && (IO.instance_method(:use_select) rescue nil)
							mi = m.to_i
							mstd = m.std_mode
							if mi & File::WRONLY != 0
								if mstd =~ /w/ && mstd !~ /\+/
									mstd.sub! /w/, "w+"
								end
							end
							ret = __org_open_____(f, mstd, perm)
							if $startDeb
								p.red ret, f, fmode
							end
							ret
						elsif fmode.sys? || fmode.nonblock?
							if $startDeb
								p f, fmode
								p `ls -la #{f}`
								p f._e?
								p IO.sysopen(f, File::WRONLY|File::NONBLOCK)
							end
							ret = IO.for_fd(IO.sysopen(f, m.to_i | File::NONBLOCK, perm), m.std_mode)
							if $startDeb
								p.red f, fmode
							end
							ret
						else
							if $startDeb
								p f, fmode
							end
							fp = __org_open_____ f, m.std_mode, perm
						end
					end
					if fmode.pmode == :pipe
						if !File.exist?(f) && fmode.creatable?
							begin
								File.mkfifo(f)
							rescue Exception => e
							end
						end
						if !File.pipe?(f)
							raise ArgumentError.new("cannot crate pipe #{f}, non-pipe file already exists.")
						end
						#if fmode.writable? && fmode.readable?
						#	hasPipeWriter = true
						#	writeFile = "#{f}.__write__"
						#	File.pipe?(f) && (File.pipe?(writeFile) || File.mkfifo(writeFile))
						#	openWithWrite = Proc.new do |a, b|
						#		fp = __org_open_____(a, fmode.to_i, perm)
						#		fp.set_write_io __org_open_____(b, fmode.to_i, perm)
						#	end
						#	if fmode.truncate?
						#		openWithWrite.call(f, writeFile)
						#	else
						#		openWithWrite.call(writeFile, f)
						#	end
						#else
							if fmode.writable? && !fmode.readable? && fmode.nonblock?
								fmode2 = fmode.clone
								fmode2.readable = true
								fp = getFp.call fmode2
								fp.fmode = fmode
							else
								fp = getFp.call fmode
							end
						#end
					else
						fp = getFp.call fmode
					end
					if fmode.delete?
						fp.__hook__ :close, f, writeFile do |_org_h, _f_h, _f_h2|
							_org_h.call
							File.exist?(_f_h) && File.delete(_f_h)
							_f_h2 and File.exist?(_f_h2) && File.delete(_f_h2)
						end
					end
					fmode.lock? and fp.flock fmode.to_flock
					fmode.truncate? and (fp.truncate(0) rescue nil)
					handleIO.call fp
				end
				if tmp_mode
					fp.__defun__ :to_s, f.clone
				end
			end
		end
		res
	end
end



class File
	def self.readable_file? (f)
		!FileTest.blockdev?(f) && !FileTest.directory?(f) && FileTest.readable?(f)
	end
	def self.writable_file? (f)
		if !File.exist? f
			File.directory?(tmp = File.dirname(f)) && File.writable?(tmp)
		else
			!FileTest.blockdev?(f) && !FileTest.directory?(f) && FileTest.writable?(f)
		end
	end
	def self.executable_file? (f)
		FileTest.executable?(f) && File.file?(f)
	end
#	def self.realpath (f)
#		Pathname.new(f).realpath.to_s
#	end
	def self.relative_path (f, d = ".")
		f = Pathname.new(f)
		d = Pathname.new(d)
		f.relative_path_from(d).to_s
	end
	def self.normalize_path (pth, defdir = nil)
		pth = File.expand_path(pth, defdir)
		if pth =~ /^\/+/
			pth = "/" + $'
		end
		if pth =~ /\/+$/
			pth = $`
		end
		pth
	end
	def self.is_in (f, d, cd = nil)
		f = File.normalize_path(f, cd)
		d = File.normalize_path(d, cd)
		if f =~ /^#{Regexp.escape d}(\/|$)/
			$'
		else
			false
		end
	end
	def self.is_in? (f, d, cd = nil)
		f = File.normalize_path(f, cd)
		d = File.normalize_path(d, cd)
		if f =~ /^#{Regexp.escape d}(\/|$)/
			$'
		else
			false
		end
	end
	def self.sibling (f, g)
		if f =~ /\/[^\/]+$/
			$` + "/" + g
		else
			g
		end
	end
	def self.resymlink (src, dst)
		if File.symlink? dst
			if File.readlink(dst) == src
				return
			else
				FileUtils.rm_f dst
				File.symlink src, dst
			end
		else
			File.symlink src, dst
		end
	end
	def self.resolv_link (l)
		if File.symlink? l
			lk = File.readlink(l)
		else
			return l
		end
		if lk =~ /^\//
			lk
		else
			File.dirname(l) + "/" + File.readlink(l)
		end
	end
	def self.fifo? (f)
		File.pipe?(f)
	end
	def self.lexist? (arg)
		File.symlink?(arg) || File.exist?(arg)
	end
	def self.exist? (arg)
		File.symlink?(arg) || File.exist?(arg)
	end
	def self.lmtime (arg)
		File.lstat(arg).mtime
	end
	def self.mknod (name, type = nil, devn = nil, mode = nil)
		if type
	    	if mode
	        	mode = "-m #{mode.to_s(8)}"
		    else
	    	    mode = ""
		    end	
			minor = devn & 0xff
			major = devn >> 8
			tp = type.chr
			system "mknod #{name} #{tp} #{mode} #{major} #{minor}"
		else
			if system "mksock #{name}"
				if mode
					File.chmod mode, name
				end
			else
				raise Exception.new("cannot create socket `#{name}'")
			end
		end
	end
	def self.mkfifo (name, mode = nil)
		if mode
			mode = "-m #{mode.to_s(8)}"
		else
			mode = ""
		end
		if !system "mkfifo #{mode} #{name}"
			raise Exception.new("cannot create fifo `#{name}'")
		end
	end
	def self.mksock (name, mode = nil)
		if !system "mksock #{name}"
			raise Exception.new("cannot create socket `#{name}'")
		end
		if mode
			FileUtils.chmod mode, name
		end
	end
	def self.partial_path (name, sub)
		arr = name.split(/\/+/)
		while arr.size != 0 && arr[-1] == ""
			arr.pop
		end
		arr[sub].join("/")
	end
	def self.delext (name, ext = nil)
		if !ext
			if name =~ /\.[^\.]*$/ && $` != ""
				return name.sub(/\.[^\.]*$/, "")
			else
				return name
			end
		end
		if ext[0] != ?.
			raise ArgumentError.new("'#{ext}' is not extension. Please add '.' before it.")
		end
		name = name.clone
		name.sub! /#{Regexp.escape ext}$/, ""
		name
	end
	def self.which (arg)
		`which #{arg}`.chomp
	end
end


class Dir
	def self.lrecursive (d)
		recursive d, false do |e|
			yield e
		end
	end
	def self.recursive d, fl = true, orgSz = nil, *exList, &bl
		_recursive({}, d, fl, orgSz, *exList, &bl)
	end
	def self._recursive (dL, d, fl = true, orgSz = nil, *exList)
		ret = []
		if d != "/" && d =~ /\/+$/
			d = $`
		end
		if orgSz == nil
			if d == "/"
				orgSz = 1
			else
				orgSz = d.size + 1
			end
		end
		if !File.directory?(d)
			return block_given? ? 0 : ret
		end
		st = File.lstat d
		s = [st.ino, st.dev]
		if dL[s]
			return
		else
			dL[s] = true
		end
		getRealPath = Proc.new do |a|
			File.realpath(a) rescue a
		end
		if exList[-1].is_a? Hash
			h = exList.pop
		else
			h = Hash.new
		end
		exList.each do |e|
			h[getRealPath.call(e)] = true
		end
		pth = getRealPath.call(d)
		if h[pth]
			return block_given? ? 0 : ret 
		end
		h[pth] = true
		cnt = 0
		begin
			Dir.foreach d do |f|
				if f != "." && f != ".."
					if d[-1] == ?/
						f = d + f
					else
						f = d + "/" + f
					end
					if (fl || !File.symlink?(f)) && File.directory?(f)
						cnt += Dir._recursive dL, f, fl, orgSz, h do |g|
							def g.dir
								File.dirname(self)
							end
							def g.base
								File.basename(self)
							end
							def g.dir?
								File.directory?(self)
							end
							g.__defun__ :recbase, g do |tmp|
								tmp[orgSz .. -1]
							end
							if block_given?
								yield g
							else
								ret.push g
							end
						end
					elsif File.exist?(f) || !fl
						def f.dir
							File.dirname(self)
						end
						def f.base
							File.basename(self)
						end
						def f.dir?
							File.directory?(self)
						end
						f.__defun__ :recbase, f do |tmp|
							tmp[orgSz .. -1]
						end
						if block_given?
							yield f
						else
							ret.push f
						end
						cnt += 1
					end
				end
			end
		rescue
			return block_given? ? 0 : []
		end
		return block_given? ? cnt : ret
	end
	def self.each (d)
		Dir.foreach d do |f|
			next if f == "." || f == ".."
			if d[-1] != ?/
				g = d + "/" + f
			else
				g = d + f
			end
			def g.dir
				File.dirname(self)
			end
			def g.base
				File.basename(self)
			end
			def g.dir?
				File.directory?(self)
			end
			yield g
		end
	end
end


require 'fileutils'


module FileUtils
  class Entry_
	begin
		begin
			File.lchmod(0644, "/")
		rescue NotImplementedError
			def File.lchmod (*args)
			end
		end
	rescue
	end
	begin
		begin 
			File.lchown(0, 0, "/")
		rescue NotImplementedError
			def File.lchown (*args)
			end
		end
	rescue
	end
    def lcopy_metadata(path)
      st = lstat()
		if !File.symlink? path
	      File.utime st.atime, st.mtime, path
		end
      begin
        File.lchown st.uid, st.gid, path
      rescue Errno::EPERM
        # clear setuid/setgid
	    File.lchmod st.mode & 01777, path
      else
        File.lchmod st.mode, path
      end
    end
  def mknod (name, type = nil, devn = nil, mode = nil)
		File.mknod(name, type, devn, mode)
	end
	def mkfifo (name, mode = nil)
		File.mkfifo(name, mode)
	end
  end
  def copy_entry(src, dest, preserve = false, dereference_root = false)
    Entry_.new(src, nil, dereference_root).traverse do |ent|
      destent = Entry_.new(dest, ent.rel, false)
      ent.copy destent.path
      ent.lcopy_metadata destent.path if preserve
    end
  end
  def copy_stat(src, dest, preserve = true, dereference_root = false)
    Entry_.new(src, nil, dereference_root).traverse do |ent|
      destent = Entry_.new(dest, ent.rel, false)
      ent.lcopy_metadata destent.path if preserve
    end
  end
  def cp_stat(src, path)
	  st = File.lstat(src)
	  if !File.symlink? path
        File.utime st.atime, st.mtime, path
      end
      begin
        File.lchown st.uid, st.gid, path
      rescue Errno::EPERM
        # clear setuid/setgid
        File.lchmod st.mode & 01777, path
      else
        File.lchmod st.mode, path
      end
  end
	module_function :copy_entry
	module_function :copy_stat
	module_function :cp_stat
end


class File
	class CannotGetLock < Exception
	end
	def try_lock_ex
		if !flock File::LOCK_EX | File::LOCK_NB
			false
		else
			true
		end
	end
	def try_lock_sh
		if !flock File::LOCK_SH | File::LOCK_NB
			false
		else
			true
		end
	end
	def lock_ex
		flock File::LOCK_EX
	end
	def lock_sh
		flock File::LOCK_SH
	end
	def unlock
		flock File::LOCK_UN
	end
	def lock (mode = "e")
		case mode
		when "e"
			flock File::LOCK_EX
		when "s"
			flock File::LOCK_SH
		when "l"
			flock(fmode.writable? ? File::LOCK_EX : File::LOCK_SH)
		else
			raise ArgumentError.new("illeagal mode, '#{mode}'")
		end
	end
	def self.__lock_failed (file)
		require 'shellwords'
		pidList = []
		if File.executable?("/usr/sbin/lsof") && File.executable?("/usr/bin/lsp")
			IO.popen "/usr/sbin/lsof #{Shellwords.escape file} 2> /dev/null"  do |r|
				r.each_line do |ln|
					pid = ln.strip.split[1]
					if pid =~ /\d+/
						pidList.push pid
					end
				end
			end
			require 'Yk/proclist'
			ProcList.refresh
			curProc = ProcList.current
			pidList = pidList.select do |e|
				if pc = ProcList.pid(e)
					if pc.isFamilyOf?(curProc)
						next false
					end
					next true
				end
				next false
			end
			if pidList.size > 0
				system "/usr/bin/lsp -a -K #{pidList.join(' ')}"
			end
		end
	end
	def self.try_lock_ex (name)
	    fr = File.open name, File::RDONLY|File::CREAT|File::NONBLOCK
	    if !fr.flock File::LOCK_EX | File::LOCK_NB
	    	$DEBUG && __lock_failed(name)
	    	if block_given?
	    		raise File::CannotGetLock.new("failed to get exclusive lock '#{name}'")
	    	end
			return nil
		end
	    if block_given?
	        begin
	            yield fr
	        ensure
	            fr.close
	        end
	    else
	    	fr
	    end
	end
	def self.setpid (name)
	    fw = File.open name, File::RDWR|File::CREAT|File::NONBLOCK
		same = fw.read.chomp == $$.to_s
	    if !fw.flock(File::LOCK_EX | File::LOCK_NB) && !same
	    	$DEBUG && __lock_failed(name)
	    	fw.close
	    	raise File::CannotGetLock.new("failed to get exclusive lock '#{name}'")
		end
		fw.pos = 0
		if !same
			fw.truncate(0)
			fw.write $$.to_i
			fw.flush
			fw.flock File::LOCK_SH
		else
			Dir.foreach "/proc/#{$$}/fd" do |ent|
				next if ent !~ /^\d+$/
				if File.symlink?(s = "/proc/#{$$}/fd/#{ent}")
					if File.readlink(s) == File.normalize_path(name)
						fw.close
						fw = IO.for_fd(ent.to_i)
						break
					end
				end
			end
		end
	    if block_given?
	        begin
	            yield fw
	        ensure
	            File.delete name
				!fw.closed? && fw.close
	        end
	    else
	    	at_exit do
	    		File.delete(name) if File.exist?(name)
	    		!fw.closed? && fw.close
	    	end
	    end
	end
	def self.try_lock_sh (name)
	    fr = File.open name, File::RDONLY|File::CREAT|File::NONBLOCK
	    if !fr.flock File::LOCK_SH | File::LOCK_NB
	    	$DEBUG && __lock_failed(name)
	    	if block_given?
	    		raise File::CannotGetLock.new("failed to get shared lock '#{name}'")
	    	end
			return nil
		end
	    if block_given? 
	        begin 
	            yield fr
	        ensure 
	            fr.close 
	        end
	    else
	    	fr
	    end
	end
	def self.lock_ex (name)
		fr = File.open name, File::RDONLY|File::CREAT|File::NONBLOCK
		fr.flock File::LOCK_EX
		if block_given?
			begin
				yield
			ensure
				fr.close
			end
		else
			fr
		end
	end
	def self.lock_sh (name)
		fr = File.open name, File::RDONLY|File::CREAT|File::NONBLOCK
		fr.flock File::LOCK_SH
		if block_given?
			begin
				yield
			ensure
				fr.close
			end
		else
			fr
		end
	end
end


