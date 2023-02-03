


require 'pathname'
require 'Yk/__defun__'
require 'Yk/__hook__'
require 'Yk/io_aux'
begin
require 'tpty'
rescue LoadError
end


(class << File; self; end).class_eval do
	alias_method :__org_open_____, :open
	at_exit do
		FileUtils.rm_rf "#{ENV['HOME']}/.tmp/#{File.basename($0)}/instances/#{$$}"
		FileUtils.rmdir("#{ENV['HOME']}/.tmp/#{File.basename($0)}/instances") rescue ""
		FileUtils.rmdir("#{ENV['HOME']}/.tmp/#{File.basename($0)}") rescue ""
	end
	def open (f, mode = "r", perm = nil)
		if f == ""
			if !File.exist? "#{ENV['HOME']}/.tmp/#{File.basename($0)}/instances/#{$$}"
				File.mkpath "#{ENV['HOME']}/.tmp/#{File.basename($0)}/instances/#{$$}"
			end
			f.replace("#{ENV['HOME']}/.tmp/#{File.basename($0)}/instances/#{$$}/tmp.#{rand(10000000000).to_s}")
			tmode = true
			fmode.delete = true
		end
		res = nil
		fmode = mode.to_fmode
		pid = nil
		handleIO = Proc.new do |h|
			pid && h.__defun__(:pid, pid)
			if block_given?
				begin
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
					res = !$?.exitstatus ? nil : res
				else
					res
				end
			else
				res = h
			end
		end
		fp = nil
		doProg = Proc.new do |cmdLine|
			if fmode.sys?
				raise ArgumentError.new("cannot use popen with sysopen")
			end
			if !fmode.terminal?
				fp, ff = nil
				if fmode.readable? && fmode.writable?
						fr, fout = IO.pipe
						pid = fork do
							fr.close
							fw.close
							STDIN.reopen fin
							fmode.stdout? && STDOUT.reopen(fout)
							fmode.stdout? && STDERR.reopen(fout)
							exec *cmdLine
						end
						fin.close
						fout.close
						fr.set_write_io fw
						fp = fr
				else
					fr, fw = IO.pipe
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
						exec *cmdLine
					end
					ff.close
				end
				handleIO.call fp
			else
				p
				fp = nil
				pty = TPty.new
				if !pty || !(fp = pty.master)
					p pty
					Exception.new("cannot allocate pseudo tty")
				end
				p
				fq = pty.slave
				p fp
				fp.set_raw
				p
				pid = fork do
					p
					Process.setsid
			#Process.setpgrp
					fqFile = "/proc/#{$$}/fd/#{pty.slave.to_i}".readlink
					fq.reopen fqFile
					STDIN.reopen fq
					STDOUT.reopen fq
					STDERR.reopen fq
					fq.close
					fp.close
					p
					exec *cmdLine
					p :failed
				end
				p pid
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
			File.pipe?(f) && fmode.pmode = :pipe
			case fmode.pmode
			when :program, :terminal
				doProg.call [f]
			else
				writeFile = nil
				getFp = Proc.new do |m|
					if fmode.sys?
						IO.for_fd IO.sysopen(f, m.to_i, perm)
					else
						__org_open_____ f, m.to_i, perm
					end
				end
				if fmode.pmode == :pipe
					if !IO::PIPE_LOCKABLE && fmode.lock? 
						raise ArgumentError.new("cannot lock pipe in this system")
					end
					if !File.exist?(f) && fmode.creatable?
						begin
							File.mkfifo(f)
						rescue Exception => e
						end
					end
					if !File.pipe?(f)
						raise ArgumentError.new("cannot crate pipe #{f}, non-pipe file already exists.")
					end
					if fmode.writable? && fmode.readable?
						hasPipeWriter = true
						writeFile = "#{f}.__write__"
						File.pipe?(f) && (File.pipe?(writeFile) || File.mkfifo(writeFile))
						openWithWrite = Proc.new do |a, b|
							fp = __org_open_____(a, fmode.to_i, perm)
							fp.set_write_io __org_open_____(b, fmode.to_i, perm)
						end
						if fmode.truncate?
							openWithWrite.call(f, writeFile)
						else
							openWithWrite.call(writeFile, f)
						end
					else
						if fmode.writable? && !fmode.readable? && fmode.nonblock?
							fmode2 = fmode.clone
							fmode2.readable = true
							fp = getFp.call fmode2
							fp.fmode = fmode
						else
							fp = getFp.call fmode
						end
					end
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
			if tmode
				fp.__defun__ :to_s, f.clone
			end
		end
		res
	end
end


require 'Yk/file_aux_old'


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
	def self.recursive (d, fl = true, orgSz = nil, *exList)
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
						cnt += Dir.recursive f, fl, orgSz, h do |g|
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
		require 'Yk/shellquote'
		pidList = []
		if File.executable?("/usr/sbin/lsof") && File.executable?("/usr/bin/lsp")
			IO.popen "/usr/sbin/lsof #{file.condSQuote} 2> /dev/null"  do |r|
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


class << Object.new
	def self.rewriteIOMethods (cls, rewrite_methods)
		cls.class_eval do
			rms = rewrite_methods.sort_by do |a|
				-a.size
			end
			def self.getLabelAndFm (e, extra = "")
				case e.to_sym
				when :write, :writeln
					fmode = IO::FMode.new extra
					fmode.writable = true
					fmode.readable = false
					fmode.creatable = true
					if !fmode.append?
						fmode.truncate = true
					end
				when :rewrite_each_line, :ref_each_line, :addlines, :addline, :dellines, :delline
					fmode = IO::FMode.new extra
					fmode.readable = true
					fmode.writable = true
					fmode.creatable = true
					fmode.truncate = false
				when :writeln_readln
					fmode = IO::FMode.new extra
					fmode.readable = true
					fmode.writable = true
					fmode.creatable = true
					fmode.truncate = true
				else
					fmode = IO::FMode.new extra
				end
				["__#{e}_____".to_sym, fmode]
			end
			rms.each do |e|
				e = e.to_sym
				self.__hook__ e, *getLabelAndFm(e) do |org, tlabel, fmode|
					#STDERR.write caller.inspect + "\n"
					#STDERR.flush
					#STDERR.write org.class.inspect + "\n"
					#STDERR.flush
					#STDERR.write org.inspect + "\n"
					#STDERR.flush
					path = org.args.shift
					#STDERR.write path + "\n"
					#STDERR.write fmode.inspect + "\n"
					File.open path, fmode do |fp|
						fp.method(tlabel).call(*org.args, &org.block)
					end
				end
			end
			self.__hook__ :method_missing do |org|
				name = org.args[0]
				if name != :__hk_org_method_B_missing
					if name.to_s =~ /^(#{rms.join('|')})_/ && (lb, fm = getLabelAndFm($1, $') rescue false)
						File.open org.args[1], fm do |fp|
							fp.method(lb).call(*org.args[2..-1], &org.block)
						end
					else
						org.call
					end
				else
					__reraise_method_missing name
				end
			end
			self.__hook__ :respond_to? do |org|
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


class IO
	def __read_____ (length = nil, offset = nil)
		pos = offset if offset
		read length
	end
	def __readlines_____ (rs = $/)
		readlines rs
	end
	def __readline_____ (rs = $/)
		readline rs
	end
	def __gets_____ (rs = $/)
		gets rs
	end
	def __readln_____ (rs = $/)
		readln rs
	end
	def __read_each_line_____ (rs = $/, &bl)
		read_each_line rs, &bl
	end
	def __foreach_____ (rs = $/)
		each_line rs do |ln|
			yield ln
		end
	end
	def __write_____ (*args)
		write *args
	end
	def __writeln_____ (*args)
		writeln *args
	end
	def __rewrite_each_line_____ (&bl)
		rewrite_each_line(&bl)
	end
	def __ref_each_line_____ (&bl)
		ref_each_line(&bl)
	end
	def __writeln_readln_____ (*args)
		writeln_readln *args
	end
	def __print_____ (*args)
		print *args
	end
	def __println_____ (*args)
		println *args
	end
	def __printf_____ (*args)
		printf *args
	end
	def __printfln_____ (*args)
		println *args
	end
	def __addline_____ (*args)
		addline *args
	end
	def __addlines_____ (*args)
		addlines *args
	end
	def __delline_____ (*args)
		delline *args
	end
	def __dellines_____ (*args)
		dellines *args
	end
end



