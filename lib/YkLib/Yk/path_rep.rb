

require 'Yk/file_aux'
require 'Yk/__hook__'

def __process_ary (*args)
	ret = []
	args.each do |e|
		if e.is_a? Array
			tmpArr = []
			e.each do |f|
				tmpArr.push yield(f)
			end
			ret.push tmpArr
		else
			ret.push yield(e)
		end
	end
	if ret.size == 1
		return ret[0]
	elsif ret.size == 0
		return nil
	else
		return ret
	end
end


class PathReplicator
	attr :root
	FileOrg = File.__hook_group
	FileUtilsOrg = FileUtils.__hook_group
	IOOrg = IO.__hook_group
	DirOrg = Dir.__hook_group
	def rep (*args)
		ret = __process_ary *args do |pth|
			pth = FileOrg.normalize_path(pth)
			if FileOrg.is_in(pth, @root)
				pth
			else
				symlinked = false
				linkReplicate = false
				arr = pth.split /\//
				arr.each_index do |i|
					e = arr[0 .. i].join("/")
					residue = arr[(i + 1) .. -1].join("/")
					if e == ""
						e = "/"
					else
						residue = "/" + residue
					end
					if @debugRootFiles[e] == nil
						stat = FileOrg.lstat(e) rescue nil
						if stat
							@debugRootFiles[e] = 0
							begin
								case stat.ftype
								when "symlink"
									if (tmp = FileOrg.readlink(e)) =~ /^\//
										if FileOrg.symlink?(tmp) || FileOrg.exist?(tmp)
											rep(tmp + residue)
										end
										FileOrg.resymlink(@root + tmp, @root + e)
									else
										tmp = FileOrg.resolv_link(e)
										if FileOrg.symlink?(tmp) || FileOrg.exist?(tmp)
											rep(tmp + residue)
										end
										FileOrg.resymlink(tmp, @root + e)
									end
									FileUtilsOrg.cp_stat(e, @root + e)
									symlinked = true
								when "directory"
									FileUtilsOrg.mkdir_p(@root + e)
									FileUtilsOrg.cp_stat(e, @root + e)
								else
									FileUtilsOrg.copy_entry(e, @root + e)
								end
							rescue => e
								STDERR.write "#{e.class}:#{e}\n"
							end
						else
							@debugRootFiles[e] = -1
						end
					end
				end
				@root + pth
			end
		end
		ret
	end
	def setModified (f)
		if @debugRootFiles[f] != -1 && @debugRootFiles[f] != nil
			@debugRootFiles[f] = 1
		end
	end
	def check
		@debugRootFiles.each_key do |e|
			if !FileOrg.symlink?(@root + e) && !FileOrg.exist?(@root + e)
				@debugRootFiles[e] = -1
			elsif @debugRootFiles[e] == -1
				@debugRootFiles[e] = 1
			end
		end
		recCheck = Proc.new do |pth|
			pth =~ /^#{Regexp.escape @root}(\/|$)/
			r = "/" + $'
			if @debugRootFiles[r] == nil
				@debugRootFiles[r] = 1
			end
			if !FileOrg.symlink?(pth) && FileOrg.directory?(pth)
				DirOrg.foreach pth do |f|
					if f != "." && f != ".."
						recCheck.call pth + "/" + f
					end
				end
			end
		end
		recCheck.call @root
	end
	def conv (*args)
		__process_ary *args do |pth|
			pth = FileOrg.normalize_path(pth)
			if FileOrg.is_in(pth, @root)
				pth
			else
				arr = pth.split /\//
				mustConv = false
				arr.each_index do |i|
					sp = arr[0..i].join("/")
					sp == "" && sp = "/"
					if @debugRootFiles[sp] == -1 || (@debugRootFiles[sp] != nil && i == arr.size - 1 && @debugRootFiles[sp] >= 0)
						mustConv = true
					end
				end
				if !mustConv
					pth
				else
					if pth == "/"
						root
					else
						root + "/" + pth
					end
				end
			end
		end
	end
	def rev (*args)
		__process_ary *args do |pth|
			if pth == @root
				"/"
			else
				if pth !~ /^#{Regexp.escape(@root)}(\/|$)/
					pth
				else
					"/" + $'
				end
			end
		end
	end
	def deleted? (pth)
		pth = FileOrg.normalize_path(pth)
		@debugRootFiles[pth] == -1
	end
	def altered? (pth)
		pth = FileOrg.normalize_path(pth)
		@debugRootFiles[pth] == 1
	end
	def initialize (r)
		@root = r
		@debugRootFiles = Hash.new
		if FileOrg.normalize_path(r) == "/"
			raise ArgumentError.new("cannot replicate to '/'")
		end
	end
	def setDefault (obj)
		@@default = obj
	end
	def normalizeReplicated
		normList = Hash.new
		@debugRootFiles.each do |k, v|
			if v == 1
				arr = k.split(/\//)
				arr.each_index do |i|
					tmp = arr[0..i].join("/")
					if tmp == ""
						tmp = "/"
					end
					normList[tmp] = true
				end
			end
		end
		@debugRootFiles.each_key do |k|
			if !normList[k]
				FileUtilsOrg.rm_f @root + k
			elsif FileOrg.symlink? @root + k
				lnk = FileOrg.readlink @root + k
				if lnk =~ /^#{Regexp.escape @root}(\/|$)/
					lnk = "/" + $'
					FileUtilsOrg.ln_sf @root + k, lnk
				end
			end
		end
	end
	def PathReplicator.default
		@@default
	end
	@@default = nil
	def PathReplicator.[] (*args)
		if @@default
			@@default.conv(*args)
		else
			if args.size <= 1
				args[0]
			else
				args
			end
		end
	end
	def PathReplicator.conv (*args)
		if @@default
			@@default.conv(*args)
		else
			if args.size <= 1
				args[0]
			else
				args
			end
		end
	end
	def PathReplicator.rep (*args)
		if @@default
			begin
				ret = cv = @@default.rep(args)
				if ret.size <= 1
					ret = ret[0]
				end
				if block_given?
					ret = yield *cv
				end
			ensure
				@@default.check
			end
			ret
		else
			if args.size <= 1
				ret = args[0]
			else
				ret = args
			end
			if block_given?
				ret = yield *args
			end
			ret
		end
	end
	def PathReplicator.rev (*args)
		if @@default
			@@default.rev(*args)
		else
			if args.size <= 1
				args[0]
			else
				args
			end
		end
	end
	def PathReplicator.deleted? (arg)
		if @@default
			@@default.deleted? arg
		else
			false
		end
	end
	def PathReplicator.root
		if @@default
			@@default.root
		else
			nil
		end
	end
	def PathReplicator.setRoot (r)
		r = File.resolv_link(r)
		@@default = PathReplicator.new(r)
		@@default.check
	end
	def PathReplicator.setModified (f)
		if @@default
			if f.is_a? Array
				f.each do |e|
					@@default.setModified(e)
				end
			else
				@@default.setModified(f)
			end
		end
	end
	def PathReplicator.normalizeReplicated
		if @@default
			@@default.normalizeReplicated
		end
	end
	def PathReplicator.check
		if @@default
			@@default.check
		end
	end
	def PathReplicator.set?
		@@default != nil
	end
end


if ENV['DEBUG'] || defined? DEBUG
	if !defined? DEBUG_ROOT
		DEBUG_ROOT = "/var/tmp/debug_rep/#{File.dirname($0)}/#{$$}/root"
		FileUtils.mkdir_p DEBUG_ROOT
	end
	PathReplicator.setRoute(DEBUG_ROOT)
end


class << File
	org = PathReplicator::FileOrg

	__hook__ :lstat do |closure|
		org.lstat PathReplicator[closure.args[0]]
	end

	__hook__ :stat do |closure|
		org.stat PathReplicator[closure.args[0]]
	end

	__hook__ :readlink do |closure|
		tmp = org.readlink PathReplicator[closure.args[0]]
		if tmp !~ /^\//
			tmp
		else
			PathReplicator.rev(closure.arg[0])
		end
	end

	__hook__ :symlink do |closure|
		begin
			if args[0] !~ /^\//
				d = File.dirname(closure.args[1])
				if d[-1] == ?/
					f = d + args[0]
				else
					f = d + "/" + closure.args[0]
				end
				PathReplicator.rep(f)
			else
				f = closure.args[0]
				closure.args[0] = PathReplicator.rep(f)
			end
			closure.args[1] = PathReplicator.rep(closure.args[1])
			org.symlink *closure.args
		ensure
			PathReplicator.check
			PathReplicator.setModified(closure.args[1])
		end
	end

	__hook__ :exist? do |closure|
		c = PathReplicator.conv(closure.args[0])
		org.exist? c
	end

	__hook__ :symlink? do |closure|
		org.symlink? PathReplicator.conv(closure.args[0])
	end

	__hook__ :chmod do |closure|
		files = closure.args[1..-1]
		mode = closure.args[0]
		PathReplicator.rep(files) do |fls|
			org.chmod mode, *fls
		end
		PathReplicator.setModified(files)
	end

	__hook__ :lchmod do |closure|
		files = closure.args[1..-1]
		mode = closure.args[0]
		PathReplicator.rep(files) do |fls|
			org.lchmod mode, *fls
		end
		PathReplicator.setModified(files)
	end

	__hook__ :chown do |closure| 
		o = closure.args[0]
		g = closure.args[1]
		files = closure.args[2..-1]
		PathReplicator.rep(files) do |fls|
			org.chown o, g, *fls
		end
		PathReplicator.setModified(files)
	end

	__hook__ :lchown do |closure|
		o = closure.args[0]
		g = closure.args[1]
		files = closure.args[2..-1]
		PathReplicator.rep(files) do |fls|
			org.lchown o, g, *fls
		end
		PathReplicator.setModified(files)
	end

	__hook__ :delete do |closure|
		files = closure.args
		PathReplicator.rep(files) do |fls|
			org.delete *fls
		end
	end

	__hook__ :unlink do |closure|
		files = closure.args
		PathReplicator.rep(files) do |fls|
			org.unlink *fls
		end
	end

	__hook__ :new do |closure|
		path = closure.args[0]
		args = closure.args[1..-1]
		bl = closure.block
		org.open(path, *args, &bl)
	end

	__hook__ :open do |closure|
		path = closure.args[0]
		args = closure.args[1..-1]
		bl = closure.block
		if path[0] != ?|
			if args.size == 0 || args[0] !~ /[w\+]/ #read
				org.open PathReplicator[args[0]], *args, &bl
			else #write
				PathReplicator.rep path do |a|
					org.open a, *args, &bl
				end
				PathReplicator.setModified(path)
			end
		else
			org.open path, *args, &bl
		end
	end

	__hook__ :rename do |closure|
		PathReplicator.rep closure.args do |fls|
			org.rename *fls
		end
		PathReplicator.setModified(closure.args[1])
	end

	__hook__ :truncate do |closure|
		file, len = closure.args
		PathReplicator.rep file do |f|
			org.truncate f, len
		end
		PathReplicator.setModified(file)
	end

	__hook__ :utime do |closure|
		atime, mtime, *files = closure.args
		PathReplicator.rep files do |fls|
			org.utime atime, mtime, *fls
		end
		PathReplicator.setModified(files)
	end

	__hook__ :atime do |closure|
		filename = closure.args[0]
		org.atime PathReplicator[filename]
	end

	__hook__ :ctime do |closure|
		filename = closure.args[0]
		org.ctime PathReplicator[filename]
	end

	__hook__ :mtime do |closure|
		filename = closure.args[0]
		org.mtime PathReplicator[filename]
	end

	__hook__ :expand_path do |closure|
		args = closure.args
		path, defalutDir = args[0], args[1]
		defaultDir = Dir.pwd
		org.expand_path path, defaultDir
	end

	__hook__ :ftype do |closure|
		filename = closure.args[0]
		org.ftype PathReplicator[filename]
	end

	__hook__ :blockdev? do |closure|
		path = closure.args[0]
		org.blockdev? PathReplicator[path]
	end

	__hook__ :chardev? do |closure|
		path = closure.args[0]
		org.chardev? PathReplicator[path]
	end

	__hook__ :directory? do |closure|
		path = closure.args[0]
		org.directory? PathReplicator[path]
	end

	__hook__ :executable? do |closure|
		path = closure.args[0]
		org.executable? PathReplicator[path]
	end

	__hook__ :executable_real? do |closure|
		path = closure.args[0]
		org.executable_real? PathReplicator[path]
	end

	__hook__ :exist? do |closure|
		path = closure.args[0]
		org.exist? PathReplicator[path]
	end

	__hook__ :file? do |closure|
		path = closure.args[0]
		org.file? PathReplicator[path]
	end

	__hook__ :grpowned? do |closure|
		path = closure.args[0]
		org.grpowned? PathReplicator[path]
	end

	__hook__ :owned? do |closure|
		path = closure.args[0]
		org.owned? PathReplicator[path]
	end

	__hook__ :identical? do |closure|
		path1 = closure.args[0]
		path2 = closure.args[1]
		org.identical? PathReplicator[path]
	end

	__hook__ :pipe? do |closure|
		path = closure.args[0]
		org.pipe? PathReplicator[path]
	end

	__hook__ :readable? do |closure|
		path = closure.args[0]
		org.readable? PathReplicator[path]
	end

	__hook__ :readable_real? do |closure|
		path = closure.args[0]
		org.readable_real? PathReplicator[path]
	end

	__hook__ :setgid? do |closure|
		path = closure.args[0]
		org.setgid? PathReplicator[path]
	end

	__hook__ :setuid? do |closure|
		path = closure.args[0]
		org.setuid? PathReplicator[path]
	end

	__hook__ :size do |closure|
		path = closure.args[0]
		org.size PathReplicator[path]
	end

	__hook__ :size? do |closure|
		path = closure.args[0]
		org.size? PathReplicator[path]
	end

	__hook__ :socket? do |closure|
		path = closure.args[0]
		org.socket? PathReplicator[path]
	end

	__hook__ :sticky? do |closure|
		path = closure.args[0]
		org.sticky? PathReplicator[path]
	end

	__hook__ :writable? do |closure|
		path = closure.args[0]
		org.writable? PathReplicator[path]
	end

	__hook__ :writable_real? do |closure|
		path = closure.args[0]
		org.writable_real? PathReplicator[path]
	end

	__hook__ :zero? do |closure|
		path = closure.args[0]
		org.zero? PathReplicator[path]
	end

end


Kernel.__hook__ :open do |closure|
	File.open(*closure.args, &closure.block)
end


class << IO
	org = PathReplicator::IOOrg

	__hook__ :sysopen do |closure|
		path, *args = closure.args
		bl = closure.block
		if args.size == 0 || args[0] !~ /[wx\+]/ #read
			org.sysopen PathReplicator[args[0]], *args, &bl
		else #write
			PathReplicator.rep path do |a|
				org.sysopen a, *args, &bl
			end
			PathReplicator.setModified(path)
		end
	end

	__hook__ :foreach do |closure|
		path, *rs = closure.args
		bl = closure.block
		org.foreach PathReplicator[path], *rs, &bl
	end

	__hook__ :read do |closure|
		path, *args = closure.args
		org.read PathReplicator[path], *args
	end

	__hook__ :readlines do |closure|
		path, *args = closure.args
		ret = PathReplicator[path]
		org.readlines ret, *args
	end

end


class << FileUtils
	org = PathReplicator::FileUtilsOrg

	__hook__ :ln_s do |closure|
		args = closure.args
		begin
			if args[0] =~ /^\//
				args[0] = PathReplicator.rep(args[0])
			else
				PathReplicator.rep(args[0])
			end
			args[1] = PathReplicator.rep(args[1])
			org.ln_s *args
		ensure
			PathReplicator.check
			PathReplicator.setModified(args[1])
		end
	end

	__hook__ :ln_sf do |closure|
		args = closure.args
		begin
			if args[0] =~ /^\//
				args[0] = PathReplicator.rep(args[0])
			else
				PathReplicator.rep(args[0])
			end
			args[1] = PathReplicator.rep(args[1])
			org.ln_sf *args
		ensure
			PathReplicator.check
			PathReplicator.setModified(args[1])
		end
	end

	__hook__ :symlink do |closure|
		args = closure.args
		begin
			if args[0] =~ /^\//
				args[0] = PathReplicator.rep(args[0])
			else
				PathReplicator.rep(args[0])
			end
			args[1] = PathReplicator.rep(args[1])
			org.symlink *args
		ensure
			PathReplicator.check
			PathReplicator.setModified(args[1])
		end
	end

	__hook__ :copy_entry do |closure|
		args = closure.args
		PathReplicator.rep args[1] do |dest|
			org.copy_entry PathReplicator.conv(args[0]), dest, *args[2..-1]
		end
		PathReplicator.setModified(args[0])
	end


	__hook__ :cp_stat do |closure|
		args = closure.args
		PathReplicator.rep args[1] do |dest|
			org.cp_stat PathReplicator.conv(args[0]), dest, *args[2..-1]
		end
		PathReplicator.setModified(args[0])
	end


	__hook__ :chmod do |closure|
		mode, list, options = closure.args
		options = {} if closure.args.size <= 2
		PathReplicator.rep list do |lst|
			org.chmod mode, lst, options
		end
		PathReplicator.setModified(list)
	end

	__hook__ :chmod_R do |closure|
		mode, list, options = closure.args
		options = {} if closure.args.size <= 2
		PathReplicator.rep list do |lst|
			org.chmod_R mode, lst, options
		end
		PathReplicator.setModified(list)
	end

	__hook__ :chown do |closure|
		user, group, list, options = closure.args
		options = {} if closure.args.size <= 3
		PathReplicator.rep list do |lst|
			org.chown user, group, lst, options
		end
		PathReplicator.setModified(list)
	end

	__hook__ :chown_R do |closure|	
		user, group, list, options = closure.args
		options = {} if closure.args.size <= 3
		PathReplicator.rep list do |lst|
			org.chown_R user, group, lst, options
		end
		PathReplicator.setModified(list)
	end

	__hook__ :copy_file do |closure|
		args = closure.args
		PathReplicator.rep args[1] do |dest|
			org.copy_file PathReplicator.conv(args[0]), dest, *args[2..-1]
		end
		PathReplicator.setModified(args[1])
	end

	__hook__ :cp do |closure|
		args = closure.args
		PathReplicator.rep args[1] do |dest|
			org.cp PathReplicator.conv(args[0]), dest, *args[2..-1]
		end
		PathReplicator.setModified(args[1])
	end

	__hook__ :copy do |closure|
		args = closure.args
		PathReplicator.rep args[1] do |dest|
			org.copy PathReplicator.conv(args[0]), dest, *args[2..-1]
		end
		PathReplicator.setModified(args[1])
	end

	__hook__ :cp_r do |closure|
		args = closure.args
		PathReplicator.rep args[1] do |dest|
			org.cp_r PathReplicator.conv(args[0]), dest, *args[2..-1]
		end
		PathReplicator.setModified(args[1])
	end

	__hook__ :install do |closure|
		args = closure.args
		PathReplicator.rep args[1] do |dest|
			org.install PathReplicator.conv(args[0]), dest, *args[2..-1]
		end
		PathReplicator.setModified(args[1])
	end

	__hook__ :ln do |closure|
		args = closure.args
		PathReplicator.rep args[0..1] do |ags|
			org.ln ags[0], ags[1], *args[2..-1]
		end
		PathReplicator.setModified(args[1])
	end

	__hook__ :link do |closure|
		args = closure.args
		PathReplicator.rep args[0..1] do |ags|
			org.link ags[0], ags[1], *args[2..-1]
		end
		PathReplicator.setModified(args[1])
	end

	__hook__ :mkdir do |closure|
		dir, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep dir do |d|
			org.mkdir d, options
		end
		PathReplicator.setModified(dir)
	end

	__hook__ :mkdir_p do |closure|
		dir, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep dir do |d|
			org.mkdir_p d, options
		end
		PathReplicator.setModified(dir)
	end

	__hook__ :mkpath do |closure|
		dir, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep dir do |d|
			org.mkpath d, options
		end
		PathReplicator.setModified(dir)
	end

	__hook__ :makedirs do |closure|
		dir, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep dir do |d|
			org.makedirs d, options
		end
		PathReplicator.setModified(dir)
	end

	__hook__ :mv do |closure|
		a, b, options = closure.args
		options = {} if closure.args.size <= 2
		PathReplicator.rep a, b do |_a, _b|
			org.mv _a, _b, options
		end
		PathReplicator.setModified(b)
	end

	__hook__ :move do |closure|
		a, b, options = closure.args
		options = {}  if closure.args.size <= 2
		PathReplicator.rep a, b do |_a, _b|
			org.move _a, _b, options
		end
		PathReplicator.setModified(b)
	end

	__hook__ :rm do |closure|
		a, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep a do |_a|
			org.rm _a, options
		end
	end

	__hook__ :remove do |closure|
		a, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep a do |_a|
			org.remove _a, options
		end
	end

	__hook__ :rm_f do |closure|
		args = closure.args
		a = args[0]
		if args.size >= 2
			options = args[1]
		else
			options = {}
		end
		PathReplicator.rep a do |_a|
			org.rm_f _a, options
		end
	end

	__hook__ :safe_unlink do |closure|
		a, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep a do |_a|
			org.safe_unlink _a, options
		end
	end

	__hook__ :rm_r do |closure|
		a, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep a do |_a|
			org.rm_r _a, options
		end
	end

	__hook__ :rm_rf do |closure|
		a, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep a do |_a|
			org.rm_rf _a, options
		end
	end

	__hook__ :rmtree do |closure|
		a, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep a do |_a|
			org.rmtree _a, options
		end
	end

	__hook__ :rmdir do |closure|
		a, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep a do |_a|
			org.rmdir _a, options
		end
	end

	__hook__ :remove_entry do |closure|
		a, force = closure.args
		force = false if closure.args.size <= 1
		PathReplicator.rep a do |_a|
			org.remove_entry _a, force
		end
	end

	__hook__ :remove_entry_secure do |closure|
		a, force = closure.args
		force = false if closure.args.size <= 1
		PathReplicator.rep a do |_a|
			org.remove_entry_secure _a, force
		end
	end

	__hook__ :remove_file do |closure|
		a, force = closure.args
		force = false if closure.args.size <= 1
		PathReplicator.rep a do |_a|
			org.remove_file _a, force
		end
	end

	__hook__ :touch do |closure|
		a, options = closure.args
		options = {} if closure.args.size <= 1
		PathReplicator.rep a do |_a|
			org.touch _a, options
		end
		PathReplicator.setModified(a)
	end

end


class << Dir
	org = PathReplicator::DirOrg

	__hook__ :delete do |closure|
		a = closure.args[0]
		PathReplicator.rep a do |_a|
			org.delete _a
		end
	end

	__hook__ :rmdir do |closure|
		a = closure.args[0]
		PathReplicator.rep a do |_a|
			org.rmdir _a
		end
	end

	__hook__ :unlink do |closure|
		a = closure.args[0]
		PathReplicator.rep a do |_a|
			org.unlink _a
		end
	end

	__hook__ :mkdir do |closure|
		a = closure.args
		PathReplicator.rep a[0] do |_a|
			org.mkdir _a, *a[1..-1]
		end
		PathReplicator.setModified(a[0])
	end

	__hook__ :[] do |closure|
		args = closure.args
		glob(args)
	end

	__hook__ :glob do |closure|
		args, *flgs = closure.args
		bl = closure.block
		if PathReplicator.set?
			if !args.is_a? Arrary
				args = [args]
			end
			args_rep = []
			args.each_index do |i|
				e = args[i]
				if e =~ /^\//
					if tmp = PathReplicator::FileOrg.is_in(e, PathReplicator.root)
						args[i] = "/" + tmp
					else
						e = PathReplicator.root + e
					end
				else
					pwd = org.pwd
					if pwd == "/"
						e = "/" + e
					else
						e =  pwd + "/" + e
					end
					if tmp = PathReplicator::FileOrg.is_in(e, PathReplicator.root)
						args[i] = "/" + tmp
					else
						e = PathReplicator.root + e
					end
				end
				args_rep.push e
			end
			ret = []
			args.each do |e|
				ret += org.glob e, *flgs
			end
			args_rep.each do |e|
				ret += PathReplicator.rev org.glob(e, *flgs)
			end
			h = Hash.new
			ret.each do |e|
				if !PathReplicator.deleted?(e)
					h[e] = true
				end
			end
			ret = h.keys
			if block_given?
				ret.each do |e|
					bl.call e
				end
				ret
			else
				ret
			end
		else
			org.glob args, *flgs, &bl
		end
	end

	__hook__ :foreach do |closure|
		path = closure.args[0]
		if PathReplicator.set?
			hash = Hash.new
			if tmp = File.is_in(path, PathReplicator.root)
				path = "/" + tmp
			end
			if PathReplicator::FileOrg.directory? path
				org.foreach path do |f|
					if f != ".." && f != "."
						hash[f] = true
					end
				end
			end
			if PathReplicator::FileOrg.directory?(tmp = PathReplicator.root + PathReplicator::FileOrg.expand_path(path))
				org.foreach tmp do |f|
					if f != ".." && f != "."
						hash[f] = true
					end
				end
			end
			if path == "/"
				path = ""
				yield ".."
			end
			yield "."
			hash.keys.each do |e|
				if !PathReplicator.deleted?(path + "/" + e)
					yield e
				end
			end
		else
			org.foreach path do |e|
				yield e
			end
		end
	end

	__hook__ :chdir do |closure|
		path = closure.args[0]
		org.chdir PathReplicator[path]
	end

	__hook__ :chroot do |closure|
		path = closure.args[0]
		org.chroot PathReplicator[path]
	end

	__hook__ :entries do |closure|
		path = closure.args[0]
		ret = []
		foreach path do |e|
			ret.push e
		end
		ret
	end

	__hook__ :getwd do |closure|
		arg = closure.args
		ret = PathReplicator.rev(org.getwd)
		ret
	end

	__hook__ :getwd do |closure|
		arg = closure.args
		org.getwd(*arg)
	end

end


class << FileTest
	org = FileTest.__hook_group

	__hook__ :blockdev? do |closure|
		path = closrue.args[0]
		org.blockdev? PathReplicator[path]
	end

	__hook__ :chardev? do |closure|
		path = closrue.args[0]
		org.chardev? PathReplicator[path]
	end

	__hook__ :directory? do |closure|
		path = closrue.args[0]
		org.directory? PathReplicator[path]
	end

	__hook__ :executable? do |closure|
		path = closrue.args[0]
		org.executable? PathReplicator[path]
	end

	__hook__ :executable_real? do |closure|
		path = closrue.args[0]
		org.executable_real? PathReplicator[path]
	end

	__hook__ :exist? do |closure|
		path = closrue.args[0]
		org.exist? PathReplicator[path]
	end

	__hook__ :exist? do |closure|
		path = closrue.args[0]
		org.exist? PathReplicator[path]
	end

	__hook__ :file? do |closure|
		path = closrue.args[0]
		org.file? PathReplicator[path]
	end

	__hook__ :grpowned? do |closure|
		path = closrue.args[0]
		org.grpowned? PathReplicator[path]
	end

	__hook__ :owned? do |closure|
		path = closrue.args[0]
		org.owned? PathReplicator[path]
	end

	__hook__ :identical? do |closure|
		path1, path2 = closure.args
		org.identical? PathReplicator[path1], PathReplicator[path2]
	end

	__hook__ :pipe? do |closure|
		path = closrue.args[0]
		org.pipe? PathReplicator[path]
	end

	__hook__ :readable? do |closure|
		path = closrue.args[0]
		org.readable? PathReplicator[path]
	end

	__hook__ :readable_real? do |closure|
		path = closrue.args[0]
		org.readable_real? PathReplicator[path]
	end

	__hook__ :setgid? do |closure|
		path = closrue.args[0]
		org.setgid? PathReplicator[path]
	end

	__hook__ :setuid? do |closure|
		path = closrue.args[0]
		org.setuid? PathReplicator[path]
	end

	__hook__ :size do |closure|
		path = closrue.args[0]
		org.size PathReplicator[path]
	end

	__hook__ :size? do |closure|
		path = closrue.args[0]
		org.size? PathReplicator[path]
	end

	__hook__ :socket? do |closure|
		path = closrue.args[0]
		org.socket? PathReplicator[path]
	end

	__hook__ :sticky? do |closure|
		path = closrue.args[0]
		org.sticky? PathReplicator[path]
	end

	__hook__ :symlink? do |closure|
		path = closrue.args[0]
		org.symlink? PathReplicator[path]
	end

	__hook__ :writable? do |closure|
		path = closrue.args[0]
		org.writable? PathReplicator[path]
	end

	__hook__ :writable_real? do |closure|
		path = closrue.args[0]
		org.writable_real? PathReplicator[path]
	end

	__hook__ :zero? do |closure|
		path = closrue.args[0]
		org.zero? PathReplicator[path]
	end

end


