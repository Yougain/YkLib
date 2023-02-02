#


require 'time'
require 'Yk/misc_tz'
require 'Yk/path_aux'
require 'Yk/shellquote'


class ProcList
	INTPRLIST = ["sh", "bash", "python", "ruby", "supervise", "rwhen", "perl" ]
	private
	class HashArr < Hash
		def insert (k, item)
			(self[k] ||= []).push item
		end
	end
	class ProcElem
		attr :pid
		attr :ppid
		attr :startTime
		attr :command
		attr :prog
		attr :progBase
		attr :childList
		attr :status
		attr :uid
		def children
			childList
		end
		attr :parent, true
		attr :mem
		attr :interpreter
		attr :interpreterBase
		def kill (sig = :TERM)
			Process.kill sig, pid
		end
		if CYGWIN
			@@timebase = Time.now.to_f - "/proc/uptime".read.split[0].to_i
		else
			@@timebase = `cat /proc/stat`.each_line{|e| break(e) if e =~ /^btime\s+/ }.split[1].to_i
		end
		if CYGWIN
			@@memTotal = "/proc/meminfo".readlines.find{|e| e =~ /^MemTotal:/}.split[1].to_i
		end
		def initialize (ln)
			if ln.is_a? String
				if !CYGWIN
					if ln =~ /\s*(\d+)\s+(\d+)\s+(\w+\s+\w+\s+\d+\s+\d+:\d+:\d+\s+\d+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+(.*)/
						@pid = $1.to_i
						@ppid = $2.to_i
						@startTime = Time.parse($3)
						@cpuTime =$5
						@status =$4
						@mem = $6
						@uid = $7.to_i
						@command = $8.chomp
						if @cpuTime =~ /:/
							r = ($`.to_i * 60 + $'.to_i) / (Time.now - @startTime).to_f
							@cpuTime = sprintf "%2.2f", r * 100
						end
					else
						raise Exception.new("cannot interpret ps output")
					end
				else
					if ln =~ /\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+([^\s]+)\s+(\d+)\s(........)\s(.*)/
						@pid = $1.to_i
						@ppid = $2.to_i
						@pgid = $3.to_i
						@winpid = $4.to_i
						@tty = $5
						@uid = $6.to_i
						statusLines = "/proc/#{@pid}/status".readlines
						if statusLines.size > 0
							@mem = sprintf "%2.1f", ("/proc/#{@pid}/status".readlines.find{|e| e =~ /VmRSS/}.split[1].to_f / @@memTotal) * 100.0
							@status = (stArr = "/proc/#{@pid}/stat".read.split)[2]
							@cpuTime = (stArr[13].to_f + stArr[14].to_f)/1000
							@cpuTime = sprintf("%3d:%02d", @cpuTime / 60, @cpuTime % 60)
							@startTime = Time.at(@@timebase + (stArr[21].to_i / 1000.0))
							if @cpuTime =~ /:/
                            	r = ($`.to_i * 60 + $'.to_i) / (Time.now - @startTime).to_f
                            	@cpuTime = sprintf "%2.2f", r * 100
                        	end
							@command = (IO.read("/proc/#{@pid}/cmdline").chomp.gsub(/\0/ ,' ')) rescue $8.chomp
						else
							@mem = "n/a"
							@status = "n/a"
							@cpuTime = "n/a "
							@startTime = "/proc/#{@pid}".ctime
							@command = "/proc/#{@pid}/exename".read
						end
					else
						raise Exception.new("cannot interpret ps output")
					end
				end
				@fd_cnt = 0
				begin
					Dir.foreach "/proc/#{@pid}/fd" do |ent|
    	            	@fd_cnt += 1 if ent =~ /^\d+$/
        	        end
					@fd_cnt = sprintf "%3d", @fd_cnt
				rescue Errno::EACCES
					@fd_cnt = " - "
				rescue Errno::ENOENT
					@fd_cnt = " - "
				end
				if false
				cmdArgs = IO.read("/proc/#{@pid}/cmdline").chomp.split(/\0/) rescue []
				firstFileArg = true
				cmdArgs.each_index do |i|
					if cmdArgs[i].relative?
						if i == 0
							begin
								cmdArgs[i] = "/proc/#{@pid}/exe".readlink.chomp
							rescue
							end
						elsif INTPRLIST.include? cmdArgs[0].basename
							if cmdArgs[i] !~ /^\-/ && firstFileArg
								firstFileArg = true
								cwd = "/proc/#{@pid}/cwd".readlink.chomp rescue nil
								if cwd
									cmdArgs[i] = (cwd / cmdArgs[i]).normalize_path
								end
							end
						end
					end
				end
				if cmdArgs.size > 1
					tmp = cmdArgs.condSQuote
					tmp.gsub! /\s+/, ' '
					tmp.gsub! /[\x00-\x1f]/, ''
					if tmp != ""
						@command = tmp
					end
				elsif cmdArgs.size == 1
					if (tmp = cmdArgs[0].strip) != ""
						@command = tmp
					end
				end
				end
			end
			c = @command
			@prog = @command[/[^\s]+/]
			@progBase = File.basename(@prog)
			if INTPRLIST.include?(@progBase)
				@interpreter = @prog
				@interpreterBase = @progBase 
				carr = @command.split /\s+/
				if tmp = carr[1..-1].find{ |e| e[0] != ?- && e !~ /^(\d|\W)+$/}
					@prog = tmp
					@progBase = File.basename(@prog)
				end
			end
			if Time.now - @startTime < 3600 * 24
				@startTimeF = @startTime.strftime("%H:%M:%S")
			else
				@startTimeF = @startTime.strftime("%m/%d %a")[0..-2]
			end
			@childList = []
		end
		def self.headLine
			if !CYGWIN
				" PID STARTTIME STAT   CPU   MEM FD    COMMAND\n"
			else
				" PID STARTTIME  WPID   CPU   MEM FD    COMMAND\n"
			end
		end
		def prInfo
			if !CYGWIN
				#sprintf("%5d %s %4s %6s %4s", @pid, @startTime.strftime("%m-%d %H:%M:%S"), @status, @cpuTime, @mem)
				sprintf("%5d %s %-4s %6s %4s %3s", @pid, @startTimeF, @status, @cpuTime, @mem, @fd_cnt)
			else
				sprintf("%5d %s %5d %6s %4s %3s", @pid, @startTimeF, @winpid, @cpuTime, @mem, @fd_cnt)
				#sprintf("%5d %s", @pid, @startTime.strftime("%m-%d %H:%M:%S"))
			end
		end
		def hasDescendantsIn? (progs)
			if progs.include? self
				true
			else
				childList.each do |e|
					if e.hasDescendantsIn? progs
						return true
					end
				end
				false
			end
		end
		def getCList (progs, inChild)
			if inChild
				childList
			else
				childList.select do |e|
					e.hasDescendantsIn? progs
				end
			end
		end
		def format (w, progs, preInd = "", lst = true, inChild = false, &bl)
			def fmt (w, ln, cont)
				if cont.size >= w - 10
					cont = cont[0 ... w - 10]
				end
				ln = ln.chomp
				ln.gsub! /\t/, " "
				if w == nil || w == 0
					return ln + "\n"
				end
				if ln.size < w
					ln += "\n"
				elsif ln.size == w
					ln
				else
					ln[0...w] + fmt(w, cont + ln[w ... ln.size].strip, cont)
				end
			end
			inChild ||= progs.include? self
			ln = prInfo
			cont = " " * prInfo.size
			cList = getCList(progs, inChild)
			if preInd == ""
				if cList.size > 0
					ln += " -+ "
					cont += (lst ? "  | " : "| | ") + " " * (command[/[^\s\/]+/].size + 1)
				else
					ln += " -- "
					cont += (lst ? "    " : "|   ") + " " * (command[/[^\s\/]+/].size + 1)
				end
			else
				if cList.size > 0
					ln += preInd + " " + (lst ? "`" : "|") + "-+ "
					cont += preInd + (lst ? "   | " : " | | ") + " " * (command[/[^\s\/]+/].size + 1)
				else
					ln += preInd + " " + (lst ? "`" : "|") + "-- "
					cont += preInd + (lst ? "     " : " |   ") + " " * (command[/[^\s\/]+/].size + 1)
				end
			end
			ln += command
			ln = fmt(w, ln, cont)
			if bl
				bl.call self, ln
			end
			cLn = ""
			if preInd == ""
				nPreInd = preInd + (!lst ? "|" : " ")
			else
				nPreInd = preInd + (!lst ? " |" : "  ")
			end
			cList.each_index do |i|
				nLst = i == cList.size - 1
				cLn += cList[i].format(w, progs, nPreInd, nLst, inChild, &bl)
			end
			if inChild || cLn != ""
				ln + cLn
			else
				""
			end
		end
		def family
			if !defined? @family
				@family = [self]
				childList.each do |e|
					@family.push *e.family
				end
			end
			@family
		end
		def hasMember (m)
			family.include? m
		end
		def each
			yield self
			childList.each do |c|
				c.each do |e|
					yield e
				end
			end
		end
		def isFamilyOf? (arg)
			if arg == self
				return true
			end
			arg.childList.each do |e|
				if isFamilyOf? e
					return true
				end
			end
			return false
		end
	end
	def self.headLine
		ProcElem.headLine
	end
	def initialize
		@list = []
		@byPid = Hash.new
		@byProg = HashArr.new
		@byProgBase = HashArr.new
		if !CYGWIN
			cmd = "ps ax --cols 10000 -eo pid,ppid,lstart,stat,bsdtime,%mem,euid,command"
		else
			cmd = "ps -ael"
		end
		IO.popen cmd do |io|
			io.each_line do |ln|
				if ln =~ /^\s+PID\s/
					next
				else
					if io.pid.to_i == ln.strip.split[0].to_i
						next
					end
				end
				pe = ProcElem.new(ln)
				@list.push pe
				@byPid[pe.pid] = pe
				@byProg.insert(pe.prog, pe)
				@byProgBase.insert(pe.progBase, pe)
				if pe.interpreter
					@byProg.insert(pe.interpreter, pe)
					@byProgBase.insert(pe.interpreterBase, pe)
				end
			end
		end
		@list.each do |pe|
			pe.parent = @byPid[pe.ppid]
			if pe.parent != nil
				pe.parent.childList.push pe
			end
		end
	end
	public
	def each
		@list.each do |e|
			yield e
		end
	end
	def getUnique (arr)
		isMember = Hash.new
		arr.size.times do |i|
			arr.size.times do |j|
				if i != j
					if arr[i].hasMember arr[j]
						isMember[arr[j]] = true
					end
				end
			end
		end
		ret = []
		arr.each do |e|
			if !isMember[e]
				ret.push e
			end
		end
		return ret
	end
	@@procList = ProcList.new
	def prog (expr, match)
		case expr
		when String
			arr = expr =~ /\// ? @byProg[expr] : @byProgBase[expr]
			if arr == nil
				return []
			end
		when Regexp
			arr = []
			@list.each do |e|
				if e.command =~ expr
					arr.push e
				end
			end
		when nil
			arr = @list
		end
		if match != nil
			if match.is_a? String
				a2 = []
				arr.each do |e|
					if e.command.include? match
						a2.push e
					end
				end
				arr = a2
			elsif match.is_a? Regexp
				a2 = []
				arr.each do |e|
					if e.command =~ match
						a2.push e
					end
				end
				arr = a2
			end
		end
		arr
	end
	def pid (id)
		if id.is_a?(String) || id.is_a?(Process)
			id = id.to_i
		end
		return @byPid[id]
	end
	def find (*pidOrProg)
		id, prg, baseComp = nil, nil, nil
		pidOrProg.each do |e|
			if e.is_a? Integer
				id = e
			end
			if e.is_a? String
				prg = e
				if e !~ /\//
					baseComp = true
				else
					baseComp = false
				end
			end
		end
		if id
			if !(tmp = pid(id))
				return nil
			end
			if prg
				if baseComp
					tmp.progBase == prg ? tmp : nil
				else
					tmp.prog == prg ? tmp : nil
				end
			else
				return tmp
			end
		elsif prg
			prog(prg, nil)[0]
		else
			return nil
		end
	end
	def exist? (*pidOrProg)
		find *pidOrProg
	end
	def ProcList.pid (id)
		@@procList.pid id
	end
	def ProcList.current
		@@procList.pid $$
	end
	def ProcList.parent
		@@procList.pid($$).parent
	end
	def ProcList._findParent
		pe = current
		while true
			if yield pe
				return pe
			end
			pe = pe.parent
			if pe == nil
				break
			end
		end
		return nil
	end
	def ProcList.findParent (a)
		if (pid = a).is_a?(Integer) || (a.is_a?(Process) && pid = a.to_i)
			return _findParent { |pe| pe.pid == pid }
		else
			if a !~ /\//
				return _findParent { |pe| pe.progBase == a }
			else
				return _findParent { |pe| pe.prog == a }
			end
		end
	end
	def ProcList.prog (expr, match = nil)
		@@procList.prog expr, match
	end
	def ProcList.independent (arr)
		@@procList.getUnique arr
	end
	def ProcList.refresh
		@@procList = ProcList.new
	end
	def ProcList.exist? (*pidOrPrg)
		@@procList.exist?(*pidOrPrg)
	end
	def ProcList.find (*pidOrPrg)
		@@procList.exist?(*pidOrPrg)
	end
	def ProcList.each
		@@procList.each do |e|
			yield e
		end
	end
end


