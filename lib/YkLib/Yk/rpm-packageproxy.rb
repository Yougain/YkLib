#!/usr/bin/env ruby


require 'Yk/path_aux'
require 'rpm'
require 'Yk/set'


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
	class RetrieveError < Exception
		attr :url
		def initialize u
			super "cannot retrieve '#{u}'"
			@url = u
		end
	end
	class PackageProxy
		attr_reader :name, :version, :release, :arch, :url, :tag, :prev
		def self.fileCache
			"/var/cache/#{$0.basename}".check_dir
		end
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
						@fileName = self.class.fileCache / "#{name}-#{version}-#{release}.#{arch}.rpm"
					else
						@fileName = self.class.fileCache / @tag / "#{name}-#{version}-#{release}.#{arch}.rpm"
					end
					retRes = retrieve
				end
				#if arch != "src"
				#	@renewed = true
				#	"rpmq #{name}".read_each_line_p do |ln|
				#		begin
				#			if self <= PackageProxy.new(ln.chomp + ".rpm")
				#				@renewed = false
				#			end
				#		rescue ArgumentError
				#			next
				#		end
				#	end
				#elsif retRes
				if retRes
					@renewed = true
				end
				@renewed
			end
			@fileName
		end
		def pkgObj
			if !@pkgObj 
				@pkgObj = Package.new(fileName)
			end 
			@pkgObj
		end
		def requires
			pkgObj.requires
		end
		def files
			pkgObj.files
		end
		def provides
			pkgObj.provides
		end
		def conflicts
			pkgObj.conflicts
		end
		def [] (tag)
			pkgObj[tag]
		end
		def self.insertPkg key, np, tag = nil, mode = nil
			op = @list[tag][key]
			if mode == :ifnoent
				if op == nil
					@list[tag][key] = np
					true
				elsif op.tag == np.tag
					if op < np
						@list[tag][key] = np
						np.prev = op
						true
					else
						np.prev = op.prev
						op.prev = np
						false
					end
				else
					false
				end
			else
				if op == nil
					@list[tag][key] = np
					true
				else
					if op < np
						@list[tag][key] = np
						np.prev = op
						true
					else
						np.prev = op.prev
						op.prev = np
						false
					end
				end
			end
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
		def self.register (name, ver, rel, arch, url, tag = nil, rereg = false)
		#	if name == "bzip2"
		#		er [ver, rel, arch]
		#	end
			if !@list
				@list = Hash.new{ |h, k| h[k] = Hash.new }
				fileCache.each_entry do |e|
					if e.directory?
						e.each_entry do |e2|
							if e2.basename =~ /^(.*)\-([^\-]+)\-(^[\-]+)\.([^\.]+)\.rpm$/
								register $1, $2, $3, $4, e2, e.basename, true
							end
						end
					end
					if e.basename =~ /^(.*)\-([^\-]+)\-(^[\-]+)\.([^\.]+)\.rpm$/
						register $1, $2, $3, $4, e, nil, true
					end
				end
			end
			np = PackageProxy.new(name, ver, rel, arch, url, tag)
			if tag
				insertPkg [name, arch], np, tag
				if !rereg && insertPkg([name, arch], np, nil, :ifnoent)
					@alsoGlobal = true
				end
			else
				insertPkg [name, arch], np
			end
		end
		def self.emerge (name, arch, tag = nil)
			@list[tag][[name, arch]]
		end
		def self.installed? (name)
			rpmq name do |pkg|
				return true
			end
			return false
		end
		def initialize (n, v = nil, r = nil, a = nil, u = nil, t = nil)
			if n.is_a? PackageProxy
				@name = n.name
				@version = n.version
				@release = n.release
				@arch = n.arch
				n.url and @url = n.url
				n._fileName and @fileName = n._fileName
				n.tag and @tag = n.tag
			else
				if v
					@name = n
					@version = v
					@release = r
					@arch = a
					if u.url?
						@url = u
					else
						@fileName = u
					end
					@tag = t
				else
					if n.basename =~ /^(.*)\-([^\-]+)\-([^\-]+)\.([^\.]+)\.rpm$/
						@name = $1
						@version = $2
						@release = $3
						@arch = $4
					else
						raise ArgumentError.new("#{n} is not an RPM file.\n")
					end
					if n.url?
						@url = n
					else
						@fileName = n
					end
				end
			end
		end
		def reInit
			if @url
				@url = @url.basename / "#{name}-#{version}-#{release}.#{arch}.rpm"
				initialize @url
				@fileName = nil
			elsif @fileName
				@fileName = @fileName.basename / "#{name}-#{version}-#{release}.#{arch}.rpm"
				initialize @fileName
			end
		end
		def name= (arg)
			@name = arg
			reInit
		end
		def arch= (arg)
			@arch = arg
			reInit
		end
		def version= (arg)
			@version = arg
			reInit
		end
		def release= (arg)
			@release = arg
			reInit
		end
		def clone
			self.class.new self
		end
		def installed? (strictArch = false)
			if @arch == "src"
				raise ArgumentError.new("cannot applicable to source rpm")
			else
				self.class.rpmq name do |pkg|
					if pkg.name == @name && pkg.version == @version && pkg.release == @release
						if !strictArch
							return true
						elsif pkg.arch == @arch
							return true
						end
					end
				end
			end
			return false
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
		def self.rpmq *pkgs
			dopen do |rpmdb|
				if pkgs.size == 0
					rpmdb.each do |e|
						yield PackageProxy.new("#{e.name}-#{e.version.v}-#{e.version.r}.#{e.arch}.rpm")
					end
				else
					pkgs.each do |pkg|
						rpmdb.each_match RPM::TAG_NAME, pkg do |e|
							yield PackageProxy.new("#{e.name}-#{e.version.v}-#{e.version.r}.#{e.arch}.rpm")
						end
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
			require 'Yk/set'
			rSet = Set.new
			pSet = Set.new
			doInstall = false
			args2 = []
			args.each do |f|
			    pkg = RPM::PackageProxy.new(f)
				if !pkg.installed?(true)
				    pSet.insert pkg
				    pkg.requires.each do |e|
						e = e.name
						next if e =~ /\// || e =~ /\(/ || e =~ /\.so(\.\d+|)$/
						rSet.insert e
					end
					args2.push f
				end
			end
			if args2.size == 0
				return true
			end
			args = args2
			pSet.each do |pkg|
			    rSet.delete pkg.name
			end
			installedLst = Hash.new
			if rSet.size > 0
				retrying = true
				while retrying
					retrying = false
					print "updating " + rSet.to_a.join(' '), "\n"
				    (%W{yumf update} + rSet.to_a + ["2>&1"]).join(' ').read_each_line_p do |ln|
						print ln
						if ln =~ /package (.*) is already installed/
							$1 =~ /\-([^\-]+)\-([^\-]+)/
							installedLst[$`] = true
							db.each_match $` do |ins|
								ins.obsoletes.eacn do |e|
									installedLst[e.name] = true
								end
							end
						elsif ln =~ /Error: No Package Matching ([^\s]*)/
							if reps = replacings($1)
								rSet.delete $1
								rSet.insert *reps
								retrying = true
							end
						end
				    end
				end
				if $?.exitstatus != 0
					rSet.each do |e|
						!installedLst.include? e
						return false
					end
				end
			end
			if isUpdate
				flg = "U"
			else
				flg = "i"
			end
			installedLst = Hash.new
			print "updating " + args.to_a.join(' '), "\n"
			system "rpmdb_fix"
			(["rpm", "-#{flg}vh"] + args + ["2>&1"]).join(' ').read_each_line_p do |ln|
				print ln
            	if ln =~ /package (.*) is already installed/
                	$1 =~ /\-([^\-]+)\-([^\-]+)/
                    installedLst[$`] = true
                end
            end
			if $?.exitstatus != 0
				args.each do |f|
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
		def <=> (arg)
			if !arg.is_a?(PackageProxy)
				raise ArgumentError.new("cannot compare with non-PackageProxy instance #{arg.inspect}\n")
			end
			if  @name == arg.name && @arch == arg.arch
				res = RPM.vercmp(version, arg.version)
				res == 0 && res = RPM.vercmp(release, arg.release)
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
			@name == arg.name && @arch == arg.arch && @version = arg.version && @release == arg.release
		end
		def retrieve
			if fileName.exist?
				return nil
			else
				fileName.dirname.check_dir
				if system "wget", "-q", "-O", fileName, @url
					if @alsoGlobal
						fileName.ln_f fileCache / fileName.basename
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
					if ent.basename =~ /^(.*)\-([^\-]+)\-([^\-]+)\.([^\.]+)\.rpm$/
						PackageProxy.register($1, $2, $3, $4, ent, tag)
					end
				end
			end
		end
		def self.tags
			@tags
		end
		def self.emerge (url, tag = nil, pattern = nil, download = nil, rpm = nil)
			url = url.expand_path
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
			@tags.insert tag
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
							fnd = true
							PackageProxy.register($1, $2, $3, $4, ln, url.basename)
						end
						if !fnd
							@hash[ln] ||= new(ln, url.basename, pattern, download, rpm)
						end
					end
				end
			end
		end
		def checkPackageProxyPage (url, tag, pattern, download, rpm)
			print "reading #{url}..."
			STDOUT.flush
			all = nil
			begin
				all = "wget '#{url}' -q -O -".read_p
			rescue
				print "failed\n"
				print "#{$!.to_s} at retrieving #{url}.\n"
			else
				print "\n"
				cnt = 0
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
					if title =~ /^(.*)\-([^\-]+)\-([^\-]+)\.([^\.]+)\.rpm$/
						PackageProxy.register($1, $2, $3, $4, purl, tag)
						cnt += 1
					elsif purl[-1] == ?/ && purl =~ /^#{Regexp.escape url}/ && (url =~ /\/$/ || ($'[0] == ?/ || $' == ""))
						checkPackageProxyPage purl, tag, pattern, download, rpm
					end
				end
			end
			if url !~ /http:\/\/vault\.centos\.org\// && url =~ /\/5(\.\d+|)\/([^\/]+)\/SRPMS\/$/
				rn = $2
				if ["addons", "centosplus", "contrib", "cr", "extras", "fasttrack", "isos", "os", "updates"].include? rn
					if !$vault_version
						"http://vault.centos.org/".read_each_line do |ln|
							if ln =~ /href\s*\=\s*([\"\']|)5\.(\d+)(\/|)\1/
								$vault_version ||= 0
								if $vault_version < $2.to_i
									$vault_version = $2.to_i
								end
							end
						end
					end
					if $vault_version
						checkPackageProxyPage "http://vault.centos.org/5.#{$vault_version}/#{rn}/SRPMS/", tag, pattern, download, rpm
					end
				end
			end
			if $?.exitstatus != 0
				raise RetrieveError.new(url)
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
				urls = getURLs(mode)
				if urls
					urls.each do |url|
						superclass.emerge(url, tag)
					end
				else
					STDERR.write "section [#{mode}] is not found or not enabled in /etc/yum.repos.d/\n"
				end
			end
		end
		def self.getURLs (mode)
			if !@secList
				if "/etc/redhat-release".read =~ /(\d+)(|[\.\d]+)/
					rel = $1
				end
				@secList = Hash.new
				ents = "/etc/yum.repos.d".entries - ["/etc/yum.repos.d/CentOS-Base.repo"] - "/etc/yum.repos.d/*.rpmnew".glob
				ents.unshift "/etc/yum.repos.d/CentOS-Base.repo"
				a = `uname -i`.chomp
				aa = "/etc/rpm/platform".read.strip_comment[/[^\-]+/]
				ents.each do |ent|
					curSec = url = murl = nil
					setList = Proc.new do
						if curSec
							if url
								rel && url.gsub!(/\$releasever\b/, rel)
								url.gsub!(/\$basearch\b/, a)
								url.gsub!(/\$arch\b/, aa)
							elsif murl
								rel && murl.gsub!(/\$releasever\b/, rel)
								murl.gsub!(/\$basearch\b/, a)
								murl.gsub!(/\$arch\b/, aa)
								print "reading #{murl} ... \n"
								mList = "wget '#{murl}' -q -O -".readlines_p
								if $?.exitstatus != 0 || !mList || mList.size == 0
									raise RetrieveError.new(murl)
								end
								mList.delete_if do |e|
									e.strip_comment!
									!e.significant?
								end
								url = (mList[1] || mList[0]).strip
								url.gsub!(/\$ARCH/, a)
							end
							if url
								curSet = Set.new
								if url =~ /\/#{Regexp.escape a}(\/|)$/
									curSet.insert url  #/ "RPMS/"
									curSet.insert url.sub(/\/#{Regexp.escape a}(\/|)$/, "/SRPMS/")
								else
									curSet.insert url
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
			end
			@secList[mode]
		end
	end
end



