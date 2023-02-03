#


require 'time'
require 'Yk/misc_tz'
require 'Yk/path_aux'
require 'Yk/shellquote'


INTPRLIST = ["/bin/sh", "/bin/ruby", "/bin/bash", "/usr/bin/bash", "/usr/bin/python", "/usr/bin/ruby", "/usr/bin/supervise" ]

class ProcInfo
	private
	class HashArr < Hash
		def insert (k, item)
			(self[k] ||= []).push item
		end
	end
	class ProcElem
		attr :pid
		attr :ppid
		attr :prog
		attr :parent, true
		attr :interpreter
		attr :interpreterBase
		attr :startTime
		attr :args
		attr :cmdline
		attr :cwd
		def exe
			@prog
		end
		if CYGWIN
			@@timebase = Time.now.to_f - "/proc/uptime".read.split[0].to_i
		else
			@@timebase = `cat /proc/stat`.each_line{|e| break(e) if e =~ /^btime\s+/ }.split[1].to_i
		end
		if CYGWIN
			JiffiesRatio = 1000.0
		else
			JiffiesRatio = 100.0
		end
		def kill (sig = :TERM)
			Process.kill sig, pid
		end
		def	infoDir
			"/proc/#{@pid}"
		end
		@@allList = Hash.new
		def parent
			@parent ||= @ppid != 0 && self.class.new(@ppid)
		end
		def initialize (pid)
			@pid = pid
			@ppid = (statArr = (infoDir / "stat").read.split)[3].to_i
			@args = (carr = (infoDir / "cmdline")._?._rf?.read.split("\0"))[1..-1].__it
			@cmdline = carr.__and?.condSQuote.__it
			if (infoDir / "exe").exist?
				@prog = (infoDir / "exe").readlink.chomp rescue nil
			end
			@cwd = (infoDir / "cwd").readlink.chomp rescue nil
			@_startTime = statArr[21].to_i;
			@startTime = Time.at(@@timebase + (@_startTime  / JiffiesRatio))
			if INTPRLIST.include?(@prog)
				@interpreter = @prog
				if tmp = @args.each_index{ |i| @args[i][0] != ?- && (tmp = @args.delete_at(i); break(tmp)) }
					if tmp.is_a?(String)
						if tmp.relative?
							@prog = (@cwd / tmp).normalize_path
						else
							@prog = tmp
						end
					end
				end
			end
			@@allList[pid] = self
		end
		def setProcessStatus ps
			@processStatus = ps
		end
		def exited?
			@processStatus && @processStatus.exited?
		end
		def exitstatus
			@processStatus && @processStatus.exitstatus
		end
		def env
			if !@env
				@env = Hash.new
				arr = (infoDir / "environ").read.split("\0")
				arr.each do |e|
					if e =~ /\=/
						@env[$`] = $'
					end
				end
				@env
			else
				@env
			end
		end
		def children
			if !@children
				@children = []
				"/proc".each_entry do |f|
					if f.basename =~ /^(\d+)$/ && f._d? && (f / "environ")._rf?
						if (f / "stat").read.split[3].to_i == @pid
							@children.push ProcElem.new($1.to_i)
						end
					end
				end
			end
			@children
		end
		def alive?
			infoDir.exist? && ((tmp = (infoDir / "stat").read.split)[21].to_i == @_startTime) && tmp[2] != "Z"
		end
		def zombie?
			infoDir.exist? && ((tmp = (infoDir / "stat").read.split)[21].to_i == @_startTime) && tmp[2] == "Z"
		end
		def isProg? expr, match
			begin
				res = false
				if @prog == expr
					res = begin
						case match
						when nil
							true
						when Regexp
							args.find{ |e| e =~ match }
						else
							args.find{ |e| e.include?(match.to_s) }
						end
					end
				end
				res
			rescue
				false
			end
		end
		def file? (f)
			each_file do |g|
				if g == f
					return true
				end
			end
			return false
		end
		def each_file
            begin
                (infoDir / "fd").each_entry do |e|
					begin
	                    if e.basename =~ /^\d+$/ && e.symlink?
    	                    yield e.readlink
        	            end
					rescue Errno::ENOENT
					rescue Errno::EACCES
					end
                end
            rescue Errno::ENOENT
            rescue Errno::EACCES
            end
            return false
		end
		def close_files (*args)
			if args.size == 0
				(infoDir / "fd").each_entry do |e|
					if e.basename =~ /^\d+$/ && e.symlink?
						if (fd = $&.to_i) != 0 && fd != 1 && fd != 2
							begin
								IO.for_fd(fd).close
							rescue Errno::EBADF
								STDERR.write "cannot close #{e.readlink}(#{fd})\n"
							end
						end
					end
                end
			else
				(infoDir / "fd").each_entry do |e|
					if e.basename =~ /^\d+$/ && e.symlink? && args.include?(e)
						IO.for_fd($&.to_i).close
					else
						STDERR.write "#{__FILE__}:#{__LINE__}: cannot close #{e}\n"
					end
                end
			end
		end
		def kill (sig)
			Process.kill sig, pid
		end
		def term_or_kill tmout = 2
			Process.kill(:TERM, pid) rescue return(false)
			cnt = 0
			while true
				sleep 0.1
				if !alive?
					return true
				else
					cnt += 1
					if cnt > tmout * 10
						Process.kill(:KILL, pid) rescue return(false)
						return true
					end
				end
			end
		end
		def self.allList
			@@allList
		end
		def waitTerm cnt, step = 1
			waitUntil(cnt, step){!alive?}
		end
	end
	public
	def self.parent
		self.current.parent
	end
	def self.prog (expr, match = nil)
		procList = []
		"/proc".each_entry do |f|
			if f.directory? && f.basename =~ /^\d+$/ && (f / "environ")._rf?
				begin
					pElem = ProcElem.new $&.to_i
					if pElem.isProg? expr, match
						procList.push pElem
					end
				rescue Exception => e
				end
			end
		end
		procList
	end
	def self.waitProg (*args)
		nargs = []
		pargs = []
		args.each do |e|
			if e.is_a? Numeric
				nargs.push e
			else
				pargs.push e
			end
		end
		pres = nil
		res = waitUntil *nargs do
			pres = prog *pargs
			pres.size > 0
		end
		if res
			pres[0]
		else
			res
		end
	end
	def self.pid (id)
		begin
			ret = ProcElem.new(id.to_i)
		rescue
			ret = nil
		end
		ret
	end
	def self.current
		pid($$.to_i)
	end
	def self.findParent (a, m = nil)
		pe = ProcElem.new($$.to_i)
		while true
			if pe.isProg?(a, m)
				return pe
			elsif pe.pid == 1
				return nil
			else
				begin
					pe = ProcElem.new(pe.ppid)
				rescue
					return nil
				end
			end
		end
	end
	def self.each
		"/proc".each_entry do |d|
			if d._d? && d.basename =~ /^\d+$/ && (d / "environ")._rf?
				yield ProcElem.new(d.basename.to_i)
			end
		end
	end
	def self.trapChild
		trap :CHLD do
			pid, ps = Process.wait2
			ProcElem.allList[pid] && ProcElem.allList[pid].setProcessStatus(ps)
		end
	end
end


class String
	def procInfo (prg = nil)
		if exist?
			info = ProcInfo.pid(read.strip_comment.to_i)
			if info && info.prog == prg
				return info
			end
		end
		return nil
	end
	def openingProcInfo
		ret = []
		%W{/usr/sbin/lsof #{self}}.read_each_line_p do |ln|
			ret.push ProcInfo.pid(ln.strip[1].to_i)
		end
		ret
	end
end

