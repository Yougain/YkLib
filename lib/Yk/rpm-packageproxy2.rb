#!/usr/bin/env ruby


require 'tempfile'
require 'Yk/path_aux'
require 'rpm'
require 'set'
require 'Yk/__defun__'


class RepObject
	instance_methods.each do |e|
		if !["__id__", "__send__", "object_id"].include? e.to_s
			undef_method e
		end
	end
	def initialize o, a = false
		if !a
			@objs = [o]
		else
			@objs = o
		end
	end
	def method_missing m, *args, &bl
		if(bl == nil)
			nobjs = []
			@objs.each do |obj|
				obj.__send__(m, *args) do |*args2|
					nobjs.push args2[0]
				end
			end
			RepObject.new nobjs, true
		else
			@objs.each do |obj|
				obj.__send__(m, *args, &bl)
			end
		end
	end
end


class Object
	def __rep__
		RepObject.new self
	end
end


class String
	def update_rpm (*args)
		if url?
			raise ArgumentError.new("cannot use url #{self} for update_rpm")
		end
		args = args.map do |e|
			if !e.is_a? RPM::PackageProxy
				RPM::PackageProxy.new e
			else
				e
			end
		end
		if self.file?
			op = cp = RPM::PackageProxy.new(self)
			args.each do |np|
				if cp < np || cp.fileName.mtime < np.fileName.mtime
					cp = np
				end
			end
			if op != cp
				if !$DEBUG
					op.fileName.delete
				else
					STDERR.write "deleting #{op.fileName}\n"
				end
				np.fileName.cp op.fileName.dirname
			end
		elsif self.directory?
			hash = Hash.new
			self.each_entry do |ent|
				begin
					pkg = RPM::PackageProxy.new ent
					sd = [pkg.name, pkg.arch]
					if !hash[sd] || hash[sd] < pkg
						if hash[sd]
							if !$DEBUG
								hash[sd].fileName.delete
							else
								STDERR.write "deleting #{hash[sd].fileName}\n"
							end
						end
						hash[sd] = pkg
					end
				rescue ArgumentError
				end
			end
			h2 = Hash.new
			args.each do |pkg|
				sd = [pkg.name, pkg.arch]
				if !h2[sd] || h2[sd] < pkg || (h2[sd] == pkg && h2[sd].fileName.mtime < pkg.fileName.mtime)
					h2[sd] = pkg
				end
			end
			h2.each_key do |k|
				if !hash[k] || h2[k] > hash[k] || (h2[k] == hash[k] && h2[k].fileName.mtime > hash[k].fileName.mtime)
					if hash[k]
						if !$DEBUG
							hash[k].fileName.delete
						else
							STDERR.write "deleting #{hash[k].fileName}\n"
						end
					end
					h2[k].fileName.cp self
				end
			end
		end
	end
	def url?
		self =~ /^[a-z]([a-z0-9]+|):/
	end
	def http?
		self =~ /^http:/
	end
	def https?
		self =~ /^https:/
	end
	def ftp?
		self =~ /^ftp:/
	end
end


module RPM
	BARCH = `uname -i`.chomp
	ARCH = "/etc/rpm/platform".read.strip_comment[/[^\-]+/]
	OS = "/etc/rpm/platform".read.strip_comment[/[^\-]+$/]
	ALIST = {
		"x86_64" => %W{noarch i386 i586 i686 ia32e x86_64},
		"ia32e"   => %W{noarch i386 i586 i686 ia32e x86_64},
		"athlon"  => %W{noarch i386 i586 i686 athlon},
		"i686"     => %W{noarch i386 i586 i686},
		"i586"     => %W{noarch i386 i586},
		"i386"     => %W{noarch i386}
	}
	ALL_ARCS = %W{noarch i386 i586 i686 athlon ia32e x86_64}
	CACHE_DIR = ((Process.uid == 0 ? "/var/cache" : "#{ENV['HOME']}/.cache") / $0.basename).check_dir
	RPM_LIBS = []
	def self.checkRpmLib n, v, r, f
		if !@rpmLibs
			@rpmLibs = Hash.new
			start = nil
			%W{rpm -q --showrc}.read_each_line_p do |ln|
				if ln =~ /^\=\=\=\=\=\=\=\=\=\=\=\=/
					start = false
				end
				if start && ln =~ /^\s*(rpmlib\(.*?\))\s*\=\s*/
					n = $1
					v, r, e = PackageProxy.getVerRelEpoch($'.strip_comment)
					@rpmLibs[n] = PackageProxy.new(n, v, r, nil, nil, nil, e)
				end
				if ln =~ /^Features supported by rpmlib:/
					start = true
				end
			end
		end
		@rpmLibs[n]._?.isCond?(v, r, nil, f).__it
	end
	def self.readUrl url, tout = ENV['CACHCE_TIMEOUT']
		tout ||= 3600 * 12
		f = (CACHE_DIR / "readUrl").check_dir / url.md5sum
		if f._rf? && (f.mtime > Time.now - tout) || %W{wget #{url} -q -O #{f}}.system
			f.read
		else
			raise Exception.new("cannot retrieve #{url}")
		end
	end
	def self.compatibleArch a
		a == "src" || ALIST[ARCH].index(a)
	end
	def self.checkRpmFileName title
		if title =~ /^(.*)\-([^\-]+)\-([^\-]+)\.(cygwin\.|)([^\.]+)\.rpm$/
			name, ver, rel, isCygwin, arch = $1, $2, $3, $4 != "", $5
			if !compatibleArch(arch)
				return
			end
			if isCygwin
				if OS != "cygwin"
					return
				end
			elsif arch != "src"
				if OS == "cygwin"
					return
				end
			end
		end
		return name, ver, rel, arch
	end
	class << RPM
		alias_method :org_vercmp, :vercmp
		def vercmp a, b
			if a
				if b
					return org_vercmp(a, b)
				else
					return 1
				end
			else
				if b
					return -1
				else
					return 0
				end
			end
		end
	end
	class RetrieveError < Exception
		attr :url
		def initialize u
			super "cannot retrieve '#{u}'"
			@url = u
		end
	end
	class PackageProxy
		attr_reader :name, :url, :tag, :prev
		attr_accessor :alsoGlobal
		FileCache = (CACHE_DIR / "packages").check_dir
		def _fileName
			@fileName
		end
		def renewed?
			fileName
			@renewed
		end
		def prev
			@prev
		end
		def prev= (arg)
			@prev = arg
		end
		def id
			"#{@name}-#{@version}-#{release}.#{arch}"
		end
		def belongs? pkg
			while pkg
				if pkg == self
					return true
				end
				pkg = pkg.prev
			end
			return false
		end
		def fileName
			if !@fileName
				retRes = false
				if @url
					if !@tag
						@fileName = FileCache / "#{name}-#{version}-#{release}.#{arch}.rpm"
					else
						@fileName = FileCache / @tag / "#{name}-#{version}-#{release}.#{arch}.rpm"
					end
					retRes = retrieve
				end
				if retRes
					@renewed = true
				end
				@renewed
			end
			@fileName
		end
		def pkgObj
			if @life
				raise Exception.new("cannot use package file for provide directive")
			end
			if !@pkgObj && @fileName._?._rf?.__it
				@pkgObj = Package.new(@fileName)
			end 
			@pkgObj
		end
		attr_reader :requires, :provides, :conflicts
		def rec_requires rs = Set.new
			if rs.include? trueLife
				return
			else
				rs.add trueLife
			end
			@requires._?.each do |e|
				e.trueLife.rec_requires rs
			end
			rs
		end
		def trueLife
			if @life
				@life.trueLife
			else
				self
			end
		end
		def epoch
			@condition[:epoch]
		end
		def version
			@condition[:version]
		end
		def release
			@condition[:release]
		end
		def arch
			@condition[:arch]
		end
		def reInit
			if @url
        rpmBase = "#{name}-#{version}-#{release}.#{arch}.rpm"   
				@url = @url.basename / rpmBase 
				initialize @url
				@fileName = nil
			elsif @fileName
				@fileName = @fileName.basename / rpmBase
				initialize @fileName
			end
		end
		def name= (arg)
			@name = arg
			reInit
		end
		def epoch= (arg)
			@condition[:epoch] = arg
			reInit
		end
		def arch= (arg)
			@condition[:arch] = arg
			reInit
		end
		def version= (arg)
			@condition[:version] = arg
			reInit
		end
		def release= (arg)
			@condition[:release] = arg
			reInit
		end
		def btime
			if @life
				@life.btime
			else
				@btime
			end
		end
		def fullName hasEpoch = false
			if hasEpoch
				self.class.fullName name, version, release, arch, epoch, flag
			else
				self.class.fullName name, version, release, arch, nil, flag
			end
		end
		def self.fullName name, version, release, arch, epoch, flag
			res = nil
			if flag == "EQ" || flag == nil
				res = epoch ? "#{epoch}:" : ""
				res += name
				if version
					res += "-#{version}"
					if release
						res += "-#{release}"
					end
				end
				if arch
					res += "." + arch
				end
			else
				res = "#{name} #{FlagMethod[flag]} "
				if epoch
					res += "#{epoch}:"
				end
				if version
					res += version
					if release
						res += "-" + release
					end
				end
			end
			res
		end
		

		def origin
			if url
				url
			elsif @fileName._rf?
				@fileName
			else
				fullName
			end
		end
		def [] (tag)
			pkgObj[tag]
		end
		def self.normRpmNamePtr nameOrPkg
			if !nameOrPkg.respond_to? :eq?
				ver, rel, epoch, arch, flag = nil
				fnd = false
				FlagHash.each do |k, f|
					if name =~ k
						name = $`.strip;
						flag = f
						fnd = true
						ver, rel, epoch = getVerRelEpoch($'.strip)
						break
					end
				end
				if !fnd
					name, ver = getNameVer(name)
				end
				return name, ver, rel, arch, epoch, flag
			else
				flag = nil
				CHK_D.each do |k, v|
					if nameOrPkg.method(k).call
						flag = v
						break
					end
				end
				return nameOrPkg.name, nameOrPkg.version.v, nameOrPkg.version.r, nameOrPkg.arch, nil, flag
			end
		end
		class Pointer
			attr_reader :name, :ver, :rel, :arch, :epoch, :flag
			def initialize name, arch, tag, ver, rel, epoch, flag
				@name = name
				@tag = tag
				@ver = ver
				@rel = rel
				@arch = arch
				@epoch = epoch
				@flag = flag
			end
			def life
				if !@life
					@life = PackageProxy.emerge @name, @arch, @tag, @ver, @rel, @epoch, @flag
				end
				@life
			end
		end
		def self.emergePointer name, purl, life, cond
			if lf
				if flag == "EQ" && lf.name == name && lf.version == ver && lf.release == rel && (!lf.epoch || !epoch || lf.epoch == epoch)
					return
				end
				register name, ver, rel, arch, epoch, nil, nil, purl, tag, false, flag, lf
			else
				Pointer.new name, arch, tag, ver, rel, epoch, flag
			end
		end
		def inspect
			"RPM::PackageProxy:#{__id__.to_s(16)} #{@name}-#{@version}-#{@release}.#{@arch}#{life && ' (' + life.inspect.strip + ')'}"
		end
		def self.files
			@files
		end
		def addfile f
			@files[f].add self
		end
		def self.eachDoublePackages
			hash = Hash.new
			rpmq do |pkg|
				if (tmp = hash[pkg.name]) != nil
					if tmp.is_a? PackageProxy
						yield pkg
						hash[pkg.name] = true
					end
					yield pkg
				else
					hash[pkg.name] = pkg
				end
			end
		end
		def self.eachNonDefaultPackages
			hash = Hash.new{|h, k| h[k] = []}
			rpmq do |pkg|
				hash[pkg.name].push pkg
			end
			hash.each_value do |v|
				v.sort!
				pkg = v[-1]
				dpkg = @list[nil][[pkg.name, pkg.arch]]
				if dpkg && !pkg.belongs?(dpkg)
					yield pkg
				end
			end
		end
		def self.eachRedundantPackages
			hash = Hash.new{|h, k| h[k] = []}
			rpmq do |pkg|
				hash[pkg.name].push pkg
			end
			hash.each_value do |v|
				v.sort!
				v.pop
				v.each do |e|
					yield e
				end
			end
		end
		FlagHash = {/\=/ => "EQ", /\<\=/ => "LE", /\>\=/ => "GE", /\</ => "LT", /\>/ => "GT", /\!\=/ => "NE", /\<\>/ => "NE"}
		OppMethod = {"EQ" => "!=", "LE" => ">", "GE" => "<", "LT" => ">=", "GT" => "<=", "NE" => "=="}
		FlagMethod = {"EQ" => "==", "LE" => "<=", "GE" => ">=", "LT" => "<", "GT" => ">", "NE" => "!="}
		def self.getVerRelEpoch expr
			if expr =~ /\-/
				ver, rel = $`, $'
			else
				ver = expr
			end
			if ver =~ /:/
				epoch = $`
				ver = $'
			end
			return ver, rel, epoch
		end
		def self.getNameVer expr
				return name, nil
		end
		def self.getNameVerRelEpoch expr
			expr = expr.strip
			if expr =~ /\.rpm$/
				expr = $`
				expr = expr.basename
			end
			epoch = nil
			normName = Proc.new do
				if name =~ /:/
					epoch, name = $', $`
				end
			end
			case expr
			when /^\//
				name = expr
			when /^(.*)\-([^\-]+)\-([^\-]+)\.((cygwin\.|)[^\.]+)$/
				name, ver, rel, arch = $1, $2, $3, $4
				normName.call
			when /\-([^\-]+)\-([^\-]+)$/
				name, ver, rel = $1, $2, $3
				normName.call
			when /\-([^\-]+)$/
				name, ver = $1, $2
				normName.call
			end
			return name, ver, rel, epoch, arch
		end
		class Manager
			def initialize pkg = nil
				@set = Set.new
				pkg && add(pkg)
			end
			def add pkg
				@set.add pkg
			end
			def selectCond cnd
				ret = self.class.new
				@set.select(:isCond?[cnd]).each do |e|
					 ret.add e
				end
				ret
			end
			def max
				h = Hash.new
				@set.each do |e|
					if !h[e.name] || h[e.name] < e
						h[e.name] = e
					end
				end
				return h.values.sort_by(&:name)
			end
			def size
				@set.size
			end
			def trueLife
				ret = self.class.new
				@set.each do |e|
					ret.add e.trueLife
				end
				ret
			end
		end
		@list ||= Hash.new{ |h, k| h[k] = Manager.new }
		@pool ||= Hash.new
		@files ||= Hash.new{|h, k| h[k] = Manager.new }
		@missingList ||= Hash.new
		def Kernel.normCond cnd
			cnd[:flag] ||= "EQ"
			cnd.each do |k, v|
				if cnd.key?(k)
					(cnd[k] == "" || cnd[k] == nil) && cnd.delete(k)
				end
			end
		end
		def self.getNameAndPUrl nm, pu
			
		end
		def self.register name, *largs
			purl, life, cnd = nil
			files, requires, provides, conflicts = [], [], [], []
			arrs = [files, requires, provides, conflicts]
			largs.each do |e|
				case e
				when nil
				when Hash
					cnd = e
				when String
					purl = e
				when PackageProxy
					life = e
				when Array
					arrs.shift.replace e
				end
			end
			if life && name =~ /^\//
				life.addfile name
				return
			end
			normCond cnd
			name, purl = getNameAndPUrl name, purl
			if @pool.key? [name, purl, life, cnd]
				raise Exception.new("double registration of #{np.inspect}")
			else
				@pool[[name, purl, life, cnd]] = (np = PackageProxy.new(name, purl, life, files, requires, provides, conflicts, cnd))
			end
			@list[name].add np
			np.files._?.each do |f|
				@files[f].insert np
			end
			np
		end
		def self.emerge (nameOrFile, cnd = Hash.new)
			if nameOrFile =~ /^\//
				ret = @files[nameOrFile]
			else
				ret = @list[nameOrFile].selectCond(cnd)
			end
			if ret.size == 0
				if cnd
					cnd = cnd.clone
					cnd[:tag] = "__missing__"
				else
					cnd = {:tag => "__missing__"}
				end
				normCond cnd
				tmp = @missingList[[name, cnd]] ||= @pool[[name, nil, nil, cnd]]
				ret = Manager.new(tmp)
			end
			ret
		end
		class VerObj
			attr_reader :epoch, :version, :release
			def initialize e, v, r
				@epoch = e
				@version = v
				@release = r
			end
			def cmp op, a
				tmp = nil
				[[epoch, a.epoch], [version, a.version], [release, a.release]].each do |t, a|
					if a
						if !t
							return false
						elsif (tmp = RPM.vercmp(t, a)) != 0
							if tmp.method(op).call(0)
								return true
							else
								return false
							end
						end
					end
				end
				tmp ? tmp.method(op).call(0) : true
			end
			def == a
				cmp :==, a
			end
			def < a
				cmp :<, a
			end
			def > a
				cmp :>, a
			end
			def <= a
				cmp :<=, a
			end
			def >= a
				cmp :>=, a
			end
		end
		def tapCond cnd
			res = isCond? cnd
			res
		end
		def verObj
			@verObj ||= VerObj.new(@condition[:epoch], @condition[:version], @condition[:release])
		end
		def isCond? cnd
			if cnd[:tag] && @condition[:tag] != cnd[:tag]
				return false
			end
			if cnd[:name] && name != cnd[:tag]
				return false
			end
			av = VerObj.new(cnd)
			case @condition[:flag]
			when "EQ", nil
				case cnd[:flag]
				when nil, "EQ"
					verObj == av
				when "NE"
					verObj != av
				when "LE"
					verObj <= av
				when "LT"
					verObj < av
				when "GE"
					verObj >= av
				when "GT"
					verObj > av
				end
			when "NE"
				case cnd[:flag]
				when nil, "EQ"
					verObj != av
				when "LE", "LT", "GT", "GE"
					true
				end
			when "LE"
				case cnd[:flag]
				when "GT"
					verObj > av
				when "GE", "EQ", nil
					verObj >= av
				else
					true
				end
			when "GE"
				case cnd[:flag]
				when "LT"
					verObj < av
				when "LE", "EQ", nil
					verObj <= av
				else
					true
				end
			when "LT"
				case cnd[:flag]
				when "GT", "GE", "EQ", nil
					verObj > av
				else
					true
				end
			when "GT"
				case cnd[:flag]
				when "LT", "LE", "EQ", nil
					verObj < av
				else
					true
				end
			end
		end
		def self.installed? (name)
			@list[name].each do |e|
				if e.installed?
          return(true)
        end
			end
			return false
		end
		attr_reader :life, :flag
		def missing?
			@tag.to_s == "__missing__"
		end
		def initialize n, *largs
			purl = nil, lf = nil, cnd = nil
			fs, rs, ps, cs = [], [], [], []
			arrs = [fs, rs, ps, cs]
			largs.each do |e|
				case e
				when PackageProxy
					lf = e
				when Array
					arrs.shift.replace e
				when Hash
					cnd = e
				when String
					purl = e
				end
			end
			self.class.normCond cnd
			@condition = cnd
			if n.respond_to? :btime
				@btime = n.btime
			end
			if n.is_a? PackageProxy
				@name = n.name
				@condition = n.condition
				@requires = n.requires
				@conflicts = n.conflicts
				@provides = n.provides
				@files = n.files
				@life = n.life
				n.url and @url = n.url
				n._fileName and @fileName = n._fileName
				n.condition and @condition = n.condition.clone
			else
				if n.is_a? XXXXXX
					name = n.elements["name"].text
					ver, rel, epoch = (vea = n.elements["version"].attributes)["ver"], vea["rel"], vea["epoch"]
					arch = n.elements["arch"].text
					btime = n.elements["time"].attributes["build"]
					name.__defun__ :btime, btime
					purl = u / n.elements["location"].attributes["href"]
					if !RPM.compatibleArch(arch)
						next
					end
					if purl =~ /\.cygwin.(#{ALL_ARCS.join('|')}).rpm$/
						if OS != "cygwin"
							next
						end
					elsif arch != "src"
						if OS == "cygwin"
							next
						end
					end
					files, requires, provides, conflicts = []
					requires = []
					n.each_element "format/file" do |e|
						files.push e.text
					end
					this = nil
					notPrinted = true
					["requires", "provides", "conflicts"].each do |pOrR|
						n.each_element "format/rpm:#{pOrR}/rpm:entry" do |e|
							n, v, r, f = e.attributes["name"], e.attributes["ver"], e.attributes["rel"], e.attributes["flags"]
							if RPM.checkRpmLib(n, v, r, f)
								next
							end
							if pOrR == "provides" && purl
								t_purl = purl
							end
							tmp = PackageProxy.emergePointer(
								n, t_purl, nil, :version => v, :release => r, :arch => e.attributes["arch"], :epoch => e.attributes["epoch"], :flag => f, :tag => tag
							)
							tmp && eval(pOrR + ".push tmp")
						end
						if pOrR == "requires"
							this = PackageProxy.register(name, purl, requires, files, conflicts, 
								:version => ver, :release => rel, :arch => arch, :epoch => epoch, :tag => tag)
						end
					end
				elsif (n.is_a?(Package) && @pkgObj = n) || n =~ /\//
					if !n._rf?
						if n.url?
							@url = n
							fileName
						else
							raise Exception.new("cannot find #{norg}")
						end
					else
						@fileName = n
					end
					@condition = {}
					@name = pkgObj.name
					@fileName = norg
					@condition[:version] = pkgObj.version.v
					@condition[:release] = pkgObj.version.r
					@condition[:arch] = pkgObj.arch
					cnd && cnd[:tag] && (@condition[:tag] = cnd[:tag])
					[:requires, :provides, :conflicts].each do |label|
						arr = instance_variables_set '@' + label.to_s, []
						pkgObj.method(label).call.each do |e|
							n, v, r, a, e, f = normRpmNamePtr e
							if f == "EQ" && name == n && version == v && release == r
								next
							end
							flg = nil
							label == :provides && lf = self
							arr.push self.class.emergePointer(n, nil, lf, :arch => a, :tag => tag, :version => v, :release => r, :epoch => e, :flag => f)
						end
					end
					@files = @pkgObj.files
				elsif cnd && cnd[:tag] == "__missing__"
					@name = norg
					@condition = cnd
				elsif lf
					@life = lf
					@name = n
					if lf.tag
						@condition = {:tag => lf.tag}
					else
						@condition = {}
					end
				else
					@name = n
					@condition = cnd
					@files = fs
					@requires = rs
					@provides = ps
					@conflicts = cs
					if u && u.url?
						@url = u
					else
						@fileName = u
					end
					@life = life
				end
			end
		end
		def clone
			self.class.new self
		end
		def installed?
			if @installed == nil
				if @life
					@installed = @life.installed?
				else
					if @tag != "__installed__"
						@installed = false
						@list[name].select{|e| e.tag == "__installed__"}.each do |f|
							if f.isCond?(self.condition)
								@installed = true
								break
							end
						end
					else
						@installed = true
					end
				end
			end
			@installed
		end
		def self.dopen
			db = DB.open
			begin
				yield db
			ensure
				while !db.closed?
					db.close
				end
			end
		end
		CHK_D = {:lt? => "LT", :gt? => "GT", :eq? => "EQ", :le? => "LE", :ge? => "GE"}
		def self._getInstalled refresh
			dopen do |rpmdb|
				rpmdb.each do |e|
					pkg = register(e, :tag => "__installed__")
				end
			end
		end
		def self.getInstalled refresh = false
			_getInstalled refresh
			@installed
		end
		def self.getInstalledFiles refresh = false
			_getInstalled refresh
			@installedFiles
		end
		def self.rpmq *pkgs
			if pkgs.size == 0
				installed[nil].each do |e|
					yield e
				end
			else
				pkgs.each do |pkg|
					installed[e].each do |e|
						yield e
					end
				end
			end
		end
		def self.getReplacingList
			ret = Hash.new{|h, k| h[k] = []}
			dopen do |rpmdb|
				rpmdb.each do |e|
					e.obsoletes.each do |f|
						ret[f].push *e.obsoletes
					end
				end
			end
			ret
		end
		def self.replacings obsolete
			@replacingList ||= self.getReplacingList
			@replacingList[obsolete] 
		end
		def self._install (isUpdate, *args)
			pSet = Set.new
			doInstall = false
			args2 = []
			args.unique.each do |f|
			    pkg = RPM::PackageProxy.emerge(f)
				if !pkg.installed?(true)
				    pSet.add pkg
				    pkg.rec_requires.each do |e|
				    	if !e.installed?
							pSet.add e
						end
					end
					args2.push f
				end
			end
			if args2.size == 0
				return true
			end
			installedLst = Hash.new
			if isUpdate
				flg = "U"
				title = "updating "
			else
				flg = "i"
				title = "installing "
			end
			print title + args2.to_a.join(' '), "\n"
			(%W{rpm -#{flg}vh} + pSet.to_a.map(&:fileName)).read_each_line_p12 do |ln|
				print ln
            	if ln =~ /package (.*) is already installed/
                	$1 =~ /\-([^\-]+)\-([^\-]+)/
                    installedLst[$`] = true
                end
            end
			if $?.exitstatus != 0
				args2.each do |f|
					if f =~ /([^\/]+)\-([^\-]+)\-([^\-]+)/
						if !installedLst.keys.include? $1
							return false
						end
					end
				end
			end
			true
		end
		def self.update *args
			_install true, *args
		end
		def self.install *args
			_install false, *args
		end
		def archcmp a, b
			case [a.nil?, b.nil?]
			when [false, false]
				a = ALIST[ARCH].index(a)
				b = ALIST[ARCH].index(b)
				if a.nil? || b.nil?
					raise Exception.new("cannot compare architechtures, #{a} and #{b}");
				else
					a <=> b
				end
			when [true, false]
				-1
			when [false, true]
				1
			when [true, true]
				0
			end
		end
		def <=> (arg)
			if !arg.is_a?(PackageProxy)
				raise ArgumentError.new("cannot compare with non-PackageProxy instance #{arg.inspect}\n")
			end
			if @name == arg.name
				if epoch && arg.epoch && (res = RPM.vercmp(version, arg.version)) != 0
					return res
				end
				res = RPM.vercmp(version, arg.version)
				res == 0 && res = RPM.vercmp(release, arg.release)
				res == 0 && res = archcmp(arch, arg.arch)
				res
			else
				raise ArgumentError.new("cannot compare packages with diffirent names and/or architecture\n")
			end
		end
		def < (arg)
			(self <=> arg) == -1
		end
		def > (arg)
			(self <=> arg) == 1
		end
		def <= (arg)
			(tmp = (self <=> arg)) == -1 || tmp == 0
		end
		def >= (arg)
			(tmp = (self <=> arg)) == 1 || tmp == 0
		end
		def == (arg)
			!arg.is_a?(PackageProxy) and return false
			(tmp = (self <=> arg)) == 0
		end
		def retrieve
			if fileName.exist?
				return nil
			else
				fileName.dirname.check_dir
				if %W{wget -q -O #{fileName} #{@url}}.system
					if @alsoGlobal
						fileName.ln_f FileCache / fileName.basename
					end
					return fileName
				else
					if !$DEBUG
						fileName.delete rescue nil
					else
						STDERR.writeln "deleting ", fileName
					end
					raise RetrieveError.new(@url)
				end
			end
		end
		Dummy = "its-dummy"
		def updatable?
			!missing && ((tmp = RPM::PackageProxy.getInstalled[name].max) && tmp < self)
		end
		def self.packagesNecessary n
			reqPkgs = Hash.new{|h, k| h[k] = []}
			missings = []
			pkgs = emergeAll n
			pkgs.each do |e|
				if e.missing?
					missings.push e
				end
				if !reqPkgs[e.name].include? n
					reqPkgs[e.name].push n
				end
			end
			callRec = Proc.new do |pkg|
				if pkg.missing? && !missings.include?(e)
					missings.push e
				else
					pkg._?.requires.each do |e|
						rpkgs = e.emergeAll
						rpkgs.each do |rpkg|
							if !reqPkgs[e.name].include? rpkg
								reqPkgs[e.name].push rpkg
								callRec.call rpkg
							end
						end
					end
				end
			end
			pkgs.each do |e|
				callRec.call e
			end
			if missings.size == 0
				reqPkgs.keys.sort.each do |e|
					e.sort_by(&:tag).each do |e|
						if e.updatable?
							yield e
						end
					end
				end
				return true
			else
				missings.sort_by(&:name).each do |e|
					yield e
				end
				return false
			end
		end
	end


	class RepDir
		def initialize (url, tag, pattern, download, rpm)
			@url = url
			if url.url?
				if url.http? || url.https? || url.ftp?
					checkPackageProxyPage(url, tag, pattern, download, rpm)
				else
					raise ArgumentError.new("unsupported protocol used in #{url}\n")
				end
			else
				url.each_entry do |ent|
					n, v, r, a = RPM.checkRpmFileName ent.basename
					if n
						PackageProxy.register(n, v, r, a, nil, nil, ent, tag, false)
					end
				end
			end
		end
		def self.tags
			@tags
		end
		def self.emerge (url, tag = nil, pattern = nil, download = nil, rpm = nil)
			begin
				url = url.expand_path
			rescue
				raise
			end
			if !pattern
				pattern = /\shref\s*\=\s*([\"\']|)(([^\"\'\<\>]+)(\/|\.rpm))\1/
				download = 2
				rpm = 2
			end
			download ||= 0
			rpm ||= 0
			download = download.to_i
			rpm = rpm.to_i
			@tags ||= Set.new
			@tags.add tag
			if url.url? || url.directory?
				@hash ||= Hash.new
				@hash[url] ||= new(url, tag, pattern, download, rpm)
			elsif url.file?
				url.read_each_line do |ln|
					ln.strip_comment!
					if ln =~ /^\[(.*)\]$/
						@hash[ln] ||= OSRep.emerge($1.strip, url.basename)
					else
						fnd = false
						ln.gsub /\shref\s*\=\s*([\"\']|)(([^\"\'\<\>]+)(\/|\.rpm))\1/ do
							name, ver, rel, arch = RPM.checkRpmFileName $2
							if name
								fnd = true
								PackageProxy.register(name, ver, rel, arch, nil, nil, url.dirname / $&, nil, false)
							end
						end
						if !fnd
							@hash[ln] ||= new(ln, url.basename, pattern, download, rpm)
						end
					end
				end
			end
		end
		def analyzeRepo doc, tag, u
			require "rexml/document"
			require "rexml/xpath"
			require 'rexml/parsers/streamparser'
			require 'rexml/parsers/baseparser'
			require 'rexml/streamlistener'
			doc = REXML::Document.new doc
			i = 0
			REXML::XPath.each( doc, "//package") do |elem|
				PackageProxy.register(elem)
				
				
			end
		end
		def checkPackageProxyPage (url, tag, pattern, download, rpm)
			u = url.clone
			u.gsub!("$arch", ARCH)
			u.gsub!("$os", OS)
			rurl = u / "repodata/primary.xml.gz"
			tf = nil
			begin
				tf = Tempfile.new("ruby-rpm-packageproxy").tap &:close
				if tmp = RPM.readUrl(rurl)
					"#{tf.path}.gz".write tmp
					if %W{gunzip -f #{tf.path}.gz}.system
						analyzeRepo tf.path.read, tag, u
						return
					end
				end
			ensure
				(tf.path + ".gz").rm_f
			end
			all = RPM.readUrl url
			all.gsub pattern do
				title = Regexp.last_match[rpm].basename
				purl = Regexp.last_match[download]
				next if !title || !purl
				next if purl == "../"
				if purl[0] == ?/
					if url =~ /^[^\/:]+:\/\/[^\/]+/
						purl = $& / purl[1..-1]
					end
				elsif purl !~ /^[^\/]+:\/\//
					if url[-1] == ?/
						purl = url / purl
					elsif url =~ /\/([^\/]+)$/
						purl = $` / purl
					else
						purl = url / purl
					end
				end
				name, ver, rel, arch = RPM.checkRpmFileName title
				if name
					PackageProxy.register(name, ver, rel, arch, nil, nil, nil, purl, tag, false)
				elsif purl[-1] == ?/ && purl =~ /^#{Regexp.escape url}/ && (url =~ /\/$/ || ($'[0] == ?/ || $' == ""))
					checkPackageProxyPage purl, tag, pattern, download, rpm
				end
			end
		end
	end


	class OSRep < RepDir
		def self.emerge (mode, tag = nil)
			if mode =~ /\//
				if mode.directory?
					mode.each_entry do |e|
						self.emerge e
					end
				elsif mode.readable_file?
					url, pattern, download, rpm  = nil
					vars = %W{url pattern download rpm}
					mode.read_each_line do |e|
						e.strip_comment!
						if e =~ /\s*(#{vars.join('|')})\s*\=\s*/
							var, val = $1, $'
							if val =~ /^\/(.*)\/$/
								val = Regexp.new $1
							elsif val =~ /^\"(.*)\"$/ || val =~ /^\'(.*)\'$/
								val = $1
							end
							eval "#{var} = val"
						end
					end
					if !url
						STDERR.write "section [#{mode}] contains no url\n"
					end
					superclass.emerge(url, mode.basename, pattern, download, rpm)
				end
			else
				ufound = false
				[["/etc/yum.repos.d", :getURLs], ["/etc/yumy/repos.d", :getURLsy]].each do |dir, func|
					if dir.directory?
						urls = self.method(func).call(mode)
						if urls
							urls.each do |url|
								if mode
									superclass.emerge(url, tag)
								else
									if ["base", "updates", "addons", "extras"].include? url.tag
										tag = "__centos__"
									else
										tag = url.tag
									end
									superclass.emerge(url, tag)
								end
							end
							ufound = true
						end
					end
				end
				if !ufound
					STDERR.write "section [#{mode}] is not found or not enabled in /etc/yum.repos.d/\n"
				end
			end
		end
		def self.getURLsy mode
			ret = []
			"/etc/yumy/repos.d/#{mode}"._?.exist?.each_entry do |f|
				f.strip_comment!
				if f.readable_file?
					f.read_each_line do |ln|
						ln.strip_comment!
						if ln.significant?
							ret.push ln
						end
					end
				end
			end
			ret
		end
		def self.getURLs (mode)
			if !@secList
				if "/etc/redhat-release".read =~ /\d([\.\d]+)/
					rel = $&
				end
				@secList = Hash.new
				ents = "/etc/yum.repos.d".entries - ["/etc/yum.repos.d/CentOS-Base.repo"] - "/etc/yum.repos.d/*.rpmnew".glob
				ents.unshift "/etc/yum.repos.d/CentOS-Base.repo"
				ents.each do |ent|
					curSec = url = murl = nil
					setList = Proc.new do
						if curSec
							if url
								rel && url.gsub!(/\$releasever\b/, rel)
								url.gsub!(/\$basearch\b/, BARCH)
								url.gsub!(/\$arch\b/, ARCH)
							elsif murl
								rel && murl.gsub!(/\$releasever\b/, rel)
								murl.gsub!(/\$basearch\b/, BARCH)
								murl.gsub!(/\$arch\b/, ARCH)
								mList = (RPM.readUrl murl).split(/\n+/)
								#mList = %W{wget #{murl} -q -O -}.readlines_p
								if $?.exitstatus != 0 || !mList || mList.size == 0
									raise RetrieveError.new(murl)
								end
								mList.delete_if do |e|
									e.strip_comment!
									!e.significant?
								end
								url = (mList[1] || mList[0]).strip
								url.gsub!(/\$ARCH/, ARCH)
							end
							if url
								curSet = Set.new
								if url =~ /\/#{Regexp.escape ARCH}(\/|)$/
									curSet.add url  #/ "RPMS/"
									curSet.add url.sub(/\/#{Regexp.escape ARCH}(\/|)$/, "/SRPMS/")
								else
									curSet.add url
								end
								@secList[curSec] = curSet
							end
						end
					end
					ent.read_each_line do |ln|
						ln.strip_comment!
						case ln
						when /^\s*\[([^\]]*)\]/
							sec = $1
							setList.call
							curSec = sec
							murl = url = nil
						when /\bmirrorlist\s*\=\s*(.*)/
							murl = $1
						when /\bbaseurl\s*\=\s*(.*)/
							url = $1
						when /^enabled\s*\=\s*0$/
							curSec = nil
						end
					end
					setList.call
				end
				@secList.each do |k, v|
					v.__defun__ :tag, k
				end
			end
			if mode != :all
				@secList[mode]
			else
				@secList.values
			end
		end
	end
end



