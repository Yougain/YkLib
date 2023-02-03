#!/usr/bin/env ruby

require 'tempfile'
require 'pathname'
require 'Yk/file_aux'
#require 'Yk/missing_method'

# IO.read, IO.readlines, IO.foreach, IO.pipe, IO.write, IO.writeln, IO.rewrite_each_line, IO.ref_each_line, IO.addline, IO.delline
# String#read_each_line

module ExecTimeout
    def exec_timeout t
        pid = nil
        r, w = IO.pipe
        pid = fork do
            r.close
            self.exec
        end
        w.close
		res = nil
		tout = false
        begin
            if nil == IO.select([r], nil, nil, t)
				tout = true
				if block_given?
	                res = yield pid
				else
					Process.kill :TERM, pid
				end
            end
        ensure
            Process.waitpid pid
			!tout && (res = ($?.to_i == 0))
        end
		return res
    end
end


class String
    include ExecTimeout
end


class Array
    include ExecTimeout
end


class String
	def chext src, dst = nil
		if !dst
			if self =~ /\.([^\.]+)$/
				$` + src
			else
				self + src
			end
		else
			if self =~ /#{Regexp.escape src}$/
				$` + dst
			else
				self + dst
			end
		end
	end
	def chext! src, dst = nil
		replace(chext(src, dst))
		self
	end
	def chextname a, b = nil
		chext a, b
	end
	def chextname! a, b = nil
		chext! a, b
	end
	def to_file
		if File.file? self
			return self
		else
			return nil
		end
	end
	def to_dir
		if File.directory? self
			return self
		else
			return nil
		end
	end
	FCheckList = {
        ?b => :blockdev?,
        ?c => :chardev?,
        ?d => :directory?,
        ?f => :file?,
        ?L => :symlink?,
        ?p => :pipe?,
        ?S => :socket?,
        ?g => :setgid?,
        ?k => :sticky?,
        ?r => :readable?,
        ?u => :setuid?,
        ?w => :writable?,
        ?x => :executable?,
        ?e => :exist?,
        ?s => :size?,
	}
	FCheckList.each do |flag, checkMethod|
		eval %{
			def _#{flag}? &then_proc
				r = File.#{checkMethod}(self)
				if then_proc
					if r
						then_proc.call self
					else
						nil
					end
				else
					r
				end
			end
		}
	end
	alias_method :__org_method_missing__, :method_missing
	def method_missing (name, *args, **opts, &proc)
		if name.to_s =~ /^(ftest|)_(.+)\?$/
			curList = {}
			mCheckName = $2
			if (mCheckName.each_char do |c|
				if !FCheckList.key?(c) || curList[c]
					break :not_ftest
				else
					curList[c] = true
				end
			end) != :not_ftest then
				self.class.class_eval %{
					def _#{mCheckName}? &then_proc
						r = #{mCheckName.chars.map{FCheckList[_1]}.map{"File." + _1.to_s + "(self)"} * "&&"}
						if then_proc
							if r
								then_proc.call self
							else
								nil
							end
						else
							r
						end
					end
					def ftest_#{mCheckName}? &then_proc
						_#{mCheckName}? &then_proc
					end
				}
				res = true
				curList.each_key do |c|
					res &&= FileTest.method(FCheckList[c]).call(self)
				end
				if res && proc
					proc.call
				else
					res
				end
			end
		else
			if IO.respond_to? name
				IO.__send__(name, self, *args, &proc)
			else
				__org_method_missing__ name, *args, **opts, &proc
			end
		end
	end
	def respond_to_missing? name, include_private
		if name.to_s =~ /^(ftest|)_(.*)\?$/
			curList = {}
			if ($2.each_char do |c|
				if !FCheckList.key?(c) || curList[c]
					break :not_ftest
				else
					curList[c] = true
				end
			end) != :not_ftest then
				true
			else
				IO.respond_to? name, include_private
			end
		end
	end
	#delegated from IO
	%w{
		gets readline readlines write
		readln writeln rewrite_each_line ref_each_line
		writeln_readln print println printf printfln addline delline addlines dellines
	}.each do |e|
		if method_defined? e
			raise ArgumentError.new("'#{e}' already defined")
		end
		class_eval %{
			def #{e} (*args, &bl)
				IO.method(:#{e}).call(self, *args, &bl)
			end
		}
	end
	def __http_fetch (limit = 10)
		raise ArgumentError, 'http redirect too deep' if limit == 0

		response = Net::HTTP.get_response(URI.parse(self))
		case response
		when Net::HTTPSuccess     
			response
		when Net::HTTPRedirection
			res = response['location'].__http_fetch(limit - 1)
			if !res['location']
				res['location'] = response['location']
			end
			res
		else
			response.error!
		end
	end
	attr :timeout, true
	def dump_hex
		self.unpack("H*")[0]
	end
	def undump_hex
		[self].pack("H*")
	end
	def __ftp_fetch_file
		d = (Dir.home / ".tmp/Yk/path_aux/wget_cache").check_dir
		save = d / "ftp.#{$0.basename}.#{rand(100000000)}"
		f = d / dump_hex
		if timeout
			f.lock_sh do
				if Time.now - f.mtime < timeout && f.file_size != 0
					yield f
					return
				end
			end
		end
		if File.executable?("/usr/bin/axel")
			if !%W{axel #{self} -o #{save}}.system
				 raise Exception.new("cannot read #{self}")
			end
		else
			save.touch
			if !%W{wget #{self} -O #{save}}.system
				raise Exception.new("cannot read #{self}")
			end
		end
#		if self =~ /^ftp:\/\/([^\/]+)(\/|$)/
#			file = $2 + $'.chomp
#			file = "/" if file == ""
#			STDERR.write "accessing  #{$1}\n"
#			ftp = Net::FTP.open $1, "anonymous", "anonymous@anonymous.anonymous"
#			begin
#				ftp.binary = true
#				STDERR.write "reading  #{file}\n"
#				ftp.get file, save
#				STDERR.write "finished #{file} \n"
#			ensure
#				ftp.close
#			end
#		end
		begin
			f.open "lw" do |fw|
				fw.write save.read
			end
			f.lock_sh do
				yield f
			end
		ensure
			save.rm_f
		end
	end
    def __wget_file
        save = "/var/tmp/wget.#{$0.basename}.#{rand(100000000)}"
		if File.executable?("/usr/bin/axel")
			if !"axel #{!ENV['DEBUG'] ? '-v' : ''} #{self} -o #{save}".system
				 raise Exception.new("cannot read #{self}")
			end
        else
        	save.touch
			if !"wget #{!ENV['DEBUG'] ? '-q' : ''} #{self} -O #{save}".system
            	raise Exception.new("cannot read #{self}")
	        end
		end
        begin
            yield save
        ensure
            save.rm_f
        end
    end
	def read_each_line (rs = $/)
		if self =~ /^http:\/\//
			require 'net/http'
			__http_fetch.body.each_line rs do |ln|
				yield ln
			end
		elsif self =~ /^ftp:\/\//
			require 'net/ftp'
			__ftp_fetch_file do |f|
				f.read_each_line rs do |ln|
					yield ln
				end
			end
		else
			IO.read_each_line self do |ln|
				yield ln
			end
		end
	end
	def read (*args)
        if self =~ /^http:\/\//
            require 'net/http'
			f = __http_fetch.body
			args.push 
			case args.size
			when 0
	            f
			when 1
				length = args[0]
				f[0 ... length]
			when 2
				offset, length = args
				f[offset ... (offset + length)]
			end
        elsif self =~ /^ftp:\/\//
			res = nil
			__wget_file do |f|
				res = f.read
			end
			res
	   elsif !exist? && self =~ /^([a-z][\w\-]+[a-z0-9]):/
			host = $1
			escp = Regexp.escape $'
	   		prog = "require\\ \\'Yk/path_aux\\'\\;print\\'#{escp}\\'.read"
			ret = ""
		 	["ssha", $1, "ruby", "-e", prog].read_each_line_p *args do |ln|
				ret += $1 + ":" + ln
			end
			ret
	   elsif directory?
			res = ""
			each_entry do |f|
				res += f + "\n"
			end
			res
	   else
            IO.read self, *args
        end
	end
	def open (*args, &bl)
		File.open(self, *args, &bl)
	end
	alias_method :org_delete, :delete
	def delete *args
		if args.size == 0
			if self.directory?
				self.rmdir
			else
				File.delete self
			end
		else
			org_delete *args
		end
	end
	def unlink
		delete
	end
	def exist?
     	if self =~ /^(http|ftp):\/\//
     		begin
     			read
     		rescue => e
     			STDERR.write e.to_s.ln
     			return false
     		end
     		true
		else
			File.exist? self
		end
	end
	def __http_head_location
		require 'net/http'
		response = nil
		self =~ /^http:\/\/([^\/:]+)(:\d+|)/
		if $2 != ""
			prt = $2.to_i
		else
			prt = 80
		end
		Net::HTTP.start($1, prt) {|http|
			response = http.head($')
		}
		response['location']
	end
	def expand_path (defd = nil)
     	if self =~ /^http:\/\//
			s = self
			t = nil
			while true
				t = s.__http_head_location
				break if !t
				s = t
			end
			s
		elsif self =~ /^ftp:\/\//
			if self !~ /\/$/
				begin
					(self + "/").__wget_file do
					end
					if $?.to_i == 0
						return self + "/"
					else
						return self
					end
				rescue Exception
					return self
				end
			end
		elsif self !~ /^[a-z][\w\-]+[a-z0-9]:/
			File.expand_path(self, defd)
		else
			self
		end
	end
	#delegated from Dir
	%w{glob chdir chroot lrecursive recursive}.each do |e|
		class_eval %{
			def #{e} (*args, &bl)
				Dir.method(:#{e}).call(self, *args, &bl)
			end
		}
	end
	#delegated from File
	%w{
		atime ctime mtime dirname extname ftype readlink rename stat lstat
	  blockdev? chardev? directory? executable? executable_real? file? grpowned? owned?
	  identical? pipe? readable? readable_real? setgid? setuid? socket? sticky? symlink? writable?
	  writable_real? zero? setpid try_lock_sh lock_ex lock_sh locked_ex? locked_sh?
	  readable_file? writable_file? executable_file?
	  lexist? lmtime relative_path normalize_path is_in is_in? sibling resymlink resolv_link
	  fifo? mknod mkfifo mksock try_lock_ex which 
	  partial_path delext 
	}.each do |e|
		if method_defined? e
			raise ArgumentError.new("'#{e}' already defined")
		end
		class_eval %{
			def #{e} (*args, &bl)
				File.method(:#{e}).call(self, *args, &bl)
			end
		}
	end
	#delegated from Pathname
	%w{
		cd cmp compare_file copy_entry copy_file cp_r install link ln_s ln_sf
		mkdir mkdir_p mkpath makedirs mv move rm remove rm_f safe_unlink rm_r rm_rf rmtree rmdir
		remove_entry remove_entry_secure remove_file touch uptodate?
	}.each do |e|
		if method_defined? e
			raise ArgumentError.new("'#{e}' already defined")
		end
		class_eval %{
			def #{e} (*args, &bl)
				FileUtils.method(:#{e}).call(self, *args, &bl)
			end
		}
	end
	%w{
		cleanpath realpath parent mountpoint? root? relative_path_from
	}.each do |e|
		if method_defined? e
			raise ArgumentError.new("'#{e}' already defined")
		end
		class_eval %{
			def #{e} (*args, &bl)
				ret = Pathname.new(self).method(:#{e}).call(*args, &bl)
				if ret.is_a? Pathname
					ret.to_s
				else
					ret
				end
			end
		}
	end
	def relative?
		if self =~ /(\w+):\/\//
			false
		else
			Pathname.new(self).relative?
		end
	end
	def absolute?
		!relative?
	end
	def chmod (mode, **options)
		FileUtils.chmod(mode, [self], **options)
	end
	def chmod_R (mode, **options)
		FileUtils.chmod_R(mode, [self], **options)
	end
	def lchmod (mode)
		FileUtils.chmod(mode, self)
	end
	def chown (user, group, **options)
		FileUtils.chown(user, group, [self], **options)
	end
	def chown_R (user, group, **options)
		FileUtils.chown(user, group, [self], **options)
	end
	def lchown (user, group)
		File.lchown(user, group, self)
	end
	def / (arg)
		if arg == ?/
			raise ArgumentError.new("cannot concatenate abosolute path")
		elsif self[-1] != ?/
			self + "/" + arg.to_s
		else
			self + arg.to_s
		end
	end
	def cp f
		sesc = nil
		fesc = nil
		if self =~ /^(http|ftp|https):/
			__wget_file do |tmp|
				tmp.mv f
			end	
		elsif (self =~ /^[a-z][\w\-]+[a-z0-9]:/ && !exist? && eval("sesc = true")) || (f =~ /^[a-z][\w\-]+[a-z0-9]:/ && !f.exist? && eval("fesc = true"))
			s = Regexp.escape self if sesc
			f = Regexp.escape f if fesc
			["scpa", s, f].system
		else
			FileUtils.cp self, f
		end
	end
	def copy f
		cp f
	end
	def each_file
		Dir.each self do |e|
			yield e
		end
	end
	def each_entry
		Dir.each self do |e|
			yield e
		end
	end
	def entries
		ret = []
		Dir.each self do |e|
			ret.push e
		end
		ret
	end
	def symlink (arg)
		if File.exist? arg
			raise Errno::EEXIST
		end
		File.symlink self, arg
	end
	def pread_each_line
		IO.popen self do |fr|
			fr.each_line do |ln|
				yield ln
			end
		end
	end
	def file_size
		if self =~ /^([a-z][\w\-]+[a-z0-9]):/ && !exist?
			host = $1
			escp = Regexp.escape $'
	   		prog = "require\\ \\'Yk/path_aux\\'\\;print\\'#{escp}\\'.file_size.to_s"
		 	res = ["ssha", host, "ruby", "-e", prog].read_p
			if res =~ /^\d+$/
				return res.to_i
			else
				raise Exception.new("cannot get file size of #{self}")
			end
		else
			File.size(self)
		end
	end
	def relink target
		if !symlink? && _d?
			s = stat
			if target.symlink? || !target._d?
				target.rm_rf
				target.mkdir
				target.chmod s.mode
				target.mtime = s.mtime
				if Process.euid == 0
					target.chown s.uid, s.gid
				end
			else
				t = target.stat
				if s.mode != t.mode
					target.chmod s.mode
				end
				if s.mtime != t.mtime
					target.mtime = s.mtime
				end
				if Process.euid == 0
					if s.uid != t.uid || s.gid != t.gid
						target.chown s.uid, s.gid
					end
				end
			end
			each_entry do |f|
				f.relink target / f.basename
			end
		else
			st = lstat
			if target.exist?
				tst = target.stat
				if (st.dev != tst.dev) || (st.ino != tst.ino)
					target.rm_rf
					link target
				end
			else
				link target
			end
		end
	end
	def each_path
		pth = self
		if pth == ""
			return
		end
		root = false
		if pth =~ /^\/+/
			root = true
			pth = $'
		end
		if pth =~ /\/$/
			pth = $`
		end
		if pth == ""
			yield "/"
		else
			yield "/" if root
			rt = root ? "/" : ""
			arr = pth.split(/\//)
			arr.each_index do |i|
				yield rt + arr[0..i].join("/"), arr[i + 1 .. -1].join("/")
			end
		end
	end
	def reverse_each_path
		pth = self
		if pth == ""
			return
		end
		root = false
		if pth =~ /^\/+/
			root = true
			pth = $'
		end
		if pth =~ /\/$/
			pth = $`
		end
		if pth == ""
			yield "/", ""
		else
			rt = root ? "/" : ""
			arr = pth.split(/\//)
			arr.each_index do |i|
				j = arr.size - i - 1
				yield rt + arr[0..j].join("/"), arr[j + 1 .. -1].join("/")
			end
			yield "/", pth if root
		end
	end
	def basename= (arg)
		if arg != "" && arg != nil
			self.replace(self.dirname + "/" + arg)
		end
		return arg
	end
	def basename (*args)
		ags = []
		n = 0
		args.each do |e|
			if e.is_a? Integer
				n = e
			else
				ags.push e	
			end
		end
		if n == 0
			File.basename self, *ags
		else
			pre = self.split(/\//)[-(1 + n)..-2]
			if pre && pre.size > 0
				pre.push File.basename(self, *ags)
				pre.join("/")
			else
				File.basename(self, *ags)
			end
		end
	end
	class ExtManip
		def initialize (str)
			@str = str
		end
		def [] (ext)
			if @str[-ext.size .. -1] == ext
				ext.clone
			else
				nil
			end
		end
		def []= (ext, arg)
			if @str[-ext.size .. -1] == ext
				@str[-ext.size .. -1] = arg
				arg.clone
			else
				nil
			end
		end
		def == ext
			@str[-ext.size .. -1] == ext && ext.size != @str.basename.size
		end
	end
	def ext
		return ExtManip.new(self)
	end
	def check_dir
		if !File.directory? self
			FileUtils.mkdir_p self
		end
		self
	end
	def check_dirname
		if !File.directory?(tmp = File.dirname(self))
			FileUtils.mkdir_p tmp
		end
		self
	end
	def check_file
		if !File.file? self
			FileUtils.touch self
		end
		self
	end
	def mtime= (arg)
		File.utime(File.atime(self), arg, self)
		arg
	end
	DIRSTACK__ = []
	def pushd
		DIRSTACK__.push Dir.pwd
		self.cd
		if block_given?
			begin
				yield self
			ensure
				DIRSTACK__.pop.cd
			end
		end
	end
	def truncate sz = 0
		File.truncate self, sz
	end
end




class Regexp
	def each_entry
		if to_s !~ /^\(\?\-mix:(.*)\)$/
			raise ArgumentError.new("cannot use regular expression option")
		end
		i = 0
		firstFlag = false
		preExpr = ""
		esc = false
		$1.each_byte do |c|
			if !esc
				if c.chr =~ /^\W$/
					case c
					when ?^
						if i != 0
							break
						else
							firstFlag = true
							next
						end
					when ?\\
						esc = true
						next
					else 
						if !"!%&=~@`;:,/<> ".include? c
							break
						end
					end
				end
				preExpr += c.chr
			else
				esc = false
				if c.chr =~ /^\W$/
					preExpr += c.chr
				else
					break
				end
			end
			i += 1
		end
		if firstFlag
			fixedDir = nil
			if preExpr[-1] != ?/
				if preExpr.dirname.directory?
					fixedDir = preExpr.dirname
				end
			elsif preExpr.directory?
				fixedDir = preExpr
			end
			if fixedDir
				absolute = fixedDir.absolute?
				fixedDir.recursive do |f|
					if absolute
						if f =~ self
							yield f
						end
					else
						if f[fixedDir.size .. -1] =~ self
							yield f
						end
					end
				end
			end
		else
			if preExpr.absolute?
				raise ArgumentError.new("cannot process all files from root")
			else
				"./".recursive do |f|
					if f[preExpr.size .. -1] =~ self
						yield f
					end
				end
			end
		end
	end
end


class Array
	def method_missing (name, *args, **opts, &proc)
		if name == :open
			File.open(self, *args, **opts, &proc)
		else
			IO.method(name).(self, *args, **opts, &proc)
		end
	end
	def respond_to_missing? name, include_private
		name == :open or IO.respond_to_missing?(name, include_private)
	end
	#delegated from IO
	%w{
		gets readline readlines write
		readln writeln read_each_line rewrite_each_line ref_each_line
		writeln_readln print println printf printfln addline delline addlines dellines
	}.each do |e|
		if method_defined? e
			raise ArgumentError.new("'#{e}' already defined")
		end
		class_eval %{
			def #{e} (*args, **opts, &bl)
				IO.method(:#{e}).call(self, *args, **opts, &bl)
			end
		}
	end
	def read_12_each **opts
		IO.read_12_each self, **opts
	end
	def popen (*args, &bl)
		if !args[0].include? "p"
			args[0] += "p"
		end
		File.open(self, *args, &bl)
	end
end
