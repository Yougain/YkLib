#!/usr/bin/env ruby

if $debug != false
	require 'Yk/path_aux'
	require 'Yk/auto_escseq'
	require 'binding_of_caller'
	require 'Yk/eval_alt'
	#require 'Yk/inot'

	$cmdline = ([$0.basename] + ARGV).join(" ")
#	class Exception
#	    alias message_org message
#	    alias backtrace_org backtrace
#	    def ft
#	    	if backtrace[0] =~ /^(.*)?:(\d+):in/
#	    		"#{$1.basename}:#{$2}"
#	    	end
#	    end
#	    def message
#	        "---msg-start#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] #{ft} " + message_org
#	    end
#	    def backtrace
#	    	caller_locations.each do |ln|
#	    	#	system "echo 1"
#	    	end
#	    	backtrace_org#.map{|e| e + "---msg-start#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] "}
#	    end
#	end

DEBUG_FILES = {}

	$ldif = 0

	class TZDebug
		def initialize
		end
		def line f, l
			loc = caller_locations(1)[0]
			$alt_path = f
			$ldif = l - loc.lineno
		end
		def > f
			f = f.expand_path
			f.touch
			f.truncate
			$debugFileName.write f
		end
		def >> f
			f = f.expand_path
			f.touch
		#	if f.file_size > 4000000
		#		d = f.read
		#		f.write d[-4000000..-1]
		#	end
			$debugFileName.write f
		end
		def < pid
			$__orgPid__cw__.write [pid].pack("S*")
			$__orgPid__cw__.flush
		end
		Escseq::Colors.each_with_index do |e, i|
			col = e.to_s
			capCol = e.to_s.capitalize
			class_eval %{
				#{capCol} = "\\x1b[#{i + 30}m"
				Bg#{capCol} = "\\x1b[#{i + 40}m"
				def #{col} *args, &bl
					STDERR.write #{capCol}
					begin
						TZDebug.p *args, &bl
					ensure
						STDERR.write Default
						STDERR.write BgDefault
						if !bl
							STDERR.write "\r\n"
						end
					end
				end
				def bg#{capCol} *args, &bl
					STDERR.write Bg#{capCol}
					STDERR.write Black
					begin
						TZDebug.p *args, &bl
					ensure
						STDERR.write Default
						STDERR.write BgDefault
						if !bl
							STDERR.write "\r\n"
						end
					end
				end
			}
		end
		@@onStack = []
		def self.on
			@@onStack.empty? ? @@onStack.push(true) : (@@onStack[-1] ||= true)
		end
		def self.off
			@@onStack.empty? ? @@onStack.push(false) : (@@onStack[-1] &&= false)
		end
		def self.p *exprs, &bl
			if bl
				@@onStack.push exprs[0]
				begin
					ret = bl.call
				ensure
					@@onStack.pop
				end
				return ret
			end
			if !@@onStack.empty? && !@@onStack.detect{_1}
				return TZDebug.new
			end
			noLn = noTitle = false
			if Escseq::Colors.index exprs[0] 
				col = exprs.shift
			end
			locCnt = 1
			begin
				locCnt += 1
				loc = caller_locations(locCnt)[0]
			end until !["Yk/with.rb", "Yk/debug2.rb"].include?(loc.path.split(/\//)[-2..-1] * "/")
			out = ""
			if loc.path == "-" || loc.path == "(eval)" || loc.path == "-e"
				if $alt_path
					pth = $alt_path
				end
			else
				pth = loc.path
			end
			if pth
				title = "#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] #{pth.basename}:#{loc.lineno + $ldif}"
				ln = (DEBUG_FILES[pth] ||= IO.read(pth).force_encoding(Encoding::ASCII_8BIT).split(/\n/).unshift(""))[loc.lineno + $ldif]
				if ln =~ /(^|\s)p\b/
					args = $'.strip
					case args
					when /^\.line\b/, /^\>/
						out = nil
					when ""
						out = ""
					when /^\>/
						noTitle = true
						noLn = true
						out = nil
					when /^\.([\w]+)\b/
#						noTiltle = true
#						noLn = true
						func = $1
						if exprs.size == 0
							case $'.strip_comment
							when ""
								if caller_locations(1)[0].path == "(eval)"
									out = "***"
									noTitle = true
									noLn = true
								else
									out = nil
									noLn = true
								end
							when /\bdo$/
								col = func
								noTitle = true
								out = nil
								noLn = true
							else
								col = func
								out = nil
								noLn = true
							end
						else
							left = $'.strip_comment
							right = exprs.inspect[1..-2]
							if left != right
								out = "#{left} = #{right}"
							else
								out = "#{left}"
							end
							noTitle = true
							noLn = true
						end
					else
						if col
							args = args.split(/\s*,\s*/)[1..-1].join(", ")
						end
						left = args
						right = exprs.inspect[1..-2]
						if left != right
							out = "#{left} = #{right}"
						else
							out = "#{left}"
						end
					end
				end
				if !noTitle
					o = title + " "
					o = col ? (o.split[0...-1] + [o.split[-1].method(col).call]).join(" ") + " " : o
					STDERR.write o
				end
				if out
					if col
						STDERR.write out.method(col).call
					else
						STDERR.write out
					end
				end
				if !noLn
					STDERR.write "\r\n"
				end
			end
			return TZDebug.new
		end
		def self.pinit
			fr, fw = IO.pipe
			if STDERR.tty?
				lnk = "/proc/#{$$}/fd/#{STDERR.to_i}".readlink
				fe = lnk.open File::WRONLY
			else
				fe = STDERR.dup
			end
			pinfo = "" # "[#{$cmdline}:#{$$}]"
			STDERR.reopen fw
			if STDERR.respond_to? :dont_use_select
				STDERR.dont_use_select
			end
			$debugFileName = "#{ENV['HOME']}/.tmp/Yk/site_ruby/debug2.rb".check_dir / rand.to_s + ".file"
			wPids = [$$]
			cr, $__orgPid__cw__ = IO.pipe
			gr, gw = IO.pipe
			pid = fork do
				fw.close
				gr.close
				$__orgPid__cw__.close
				Process.daemon true, true
				gw.writeln $$.to_s
				gw.close
				#fe.write "#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] started debug attachment to #{wPids.join(' ')}\n"
				begin
					buff = ""
					residue = ""
					dw = dfw = nil
					debFile = ""
					interrupted = false
					loop do
						necand = nil
						serr = false
						unexpected = false
						unexpectedNext = false
						unexpectedLine = nil
						waitReaders = []
						waitReaders.push fr if fr
						waitReaders.push cr if cr
						if fr == nil && cr == nil
							break
						end
						r = nil
						if !interrupted
							begin
								r = IO.select waitReaders, [], [], 10
							rescue Exception
								interrupted = true
							end
						end
						trap :USR1 do
							if dw
								dw.write "#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] #{wPids[0]} exited.\n"
								dw.flush
								Process.kill :INT, $$
							end
						end
						if r && r[0].delete(fr)
							begin
								if debFile != (tmp = $debugFileName.read rescue nil)
									if tmp && tmp._w?
										dfw.close if dfw
										dfw = tmp.open "a"
										debFile = tmp
									end
								end
								if dfw
									dw = dfw
								else
									dw = fe
								end
								fr.readpartial 4096, buff
								buff = residue + buff
								residue.replace ""
								locked = false
								begin
									outlines = []
									head = "#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{wPids[0]}]"
									handleSerr = ->msg{
										if msg =~ /\s*(\/.*):(\d+)\s+syntax error, /
											serr = true
											msg.replace($1.basename + $2 + ":" + $')
											if msg =~ /unexpected local variable or method, /
												unexpected = true
												msg.reaplace $` + $'
											end
										end
									}
									buff.each_line do |ln|
										if ln[-1] == "\n"
											if unexpected
												unexpected = false
												unexpectedNext = true
												unexpectedLine = ln
												outlines[-1][3] += ln
											elsif unexpectedNext
												unexpectedNext = false
												s, e = ln.getStartEnd
												outlines[-1][3] += ln
												usym = unexpectedLine[s .. e]
												if ri = outlines[-1][3].rindex("expecting")
													outlines[-1][3].insert ri, "`#{usym}', "
												end
											elsif serr && handleSerr.(ln)
												outlines[-1][3] += ln
											elsif ln =~ /^Did you mean\? /
												necand = $'.strip
											elsif ln =~ /(^|\s*from )((\.+\/|\/)[^\s]+)(:(\d+):in \`(block in |)(\<(module|class)|(.*?)\'))/
												isFirst = $1 == ""
												fName = $2
												lno = $5
												msg = $'
												func = (($8 && "<#{$8}>") || $9).strip
												func.gsub! /(\w)\s+(\W)/, '\1\2'
												func.gsub! /(\W)\s+(\w)/, '\1\2'
												msg = msg.strip
												if msg =~ /^:(.*)\((.*?)\)$/
													err, msg = $2, $1.strip
													if msg =~ /\s*undefined local variable or method \`(.*?)\' for\s*/
														msg = "#{$'}::`#{$1}'"
													end
													handleSerr.(msg)
													msg = "#{head} #{err}: #{msg}\n"
												elsif msg =~ /^:/
													msg = "#{head} #{$'.strip}\n"
												elsif !msg.empty?
													msg = head + " " + msg + "\n"
												end
												if !outlines.empty? && outlines[-1][0..1] == [fName, lno] && msg == ""
													outlines[-1][2].push func
												else
													outlines.push [fName, lno, [func], msg]
												end
											else
												if dw != fe && !locked
													dw.flock File::LOCK_EX
													locked = true	
												end
												dw.write ln
											end
										else
											residue += ln
										end
									end
									prevFName = nil
									outlines.each do |fName, lno, func, msg|
										if fName == prevFName
											pFName = " " * fName.basename.size + ":"
										else
											pFName = fName.basename + ":"
										end
										lcontent = " " + String::LInfo::getFileLine(fName, lno.to_i).strip rescue ""
										pos = pFName + lno + ":(" + func * "," + ")"
										if dw != fe && !locked
											dw.flock File::LOCK_EX
											locked = true	
										end
										if necand
											msg = msg.chomp + " is `#{necand}'?\n" 
											necand = nil
										end
										dw.write msg + "> " + pos + lcontent.ln
										prevFName = fName
									end
								ensure
									dw.flush
									dw.flock File::LOCK_UN if dw != fe && locked
								end
							rescue EOFError
								fr = nil
							rescue Exception
								interrupted = true
							end
						end
						if r && r[0].delete(cr)
							begin
								if !cr.read 4, buff
									raise EOFError
								end
								if buff || buff != ""
									tpid, rpid = buff.unpack("S*")
									i = wPids.index(tpid)
									if i
										wPids[i] = rpid
										dw.write "#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] watching pid, #{tpid} changed to #{rpid}\n"
										dw.flush
									else
										wPids.push rpid
										dw.write "#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] added new pid, #{rpid}\n"
										dw.flush
									end
									#pinfo = "[#{$cmdline}:#{$__orgPid__}]"
								end
							rescue EOFError
								cr = nil
							end
						end
						if !r
							if interrupted
								dw.write "#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] interrupted.\n"
								dw.flush
							end
							wPidsExistList = wPids.map{|e|"/proc/#{e}"._e?}
							#dw.write "#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] watching, #{wPids.inspect} => #{wPidsExistList.inspect}\n"
							dw.flush
							found = false
							wPids.each do |e|
								if "/proc/#{e}"._e?
									if "/proc/#{e}/stat".read.split[2] == "Z"
										dw.write "#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] " + "pid, #{e} has become Zombie.\n".red
										dw.flush
									else
										found = true
									end
								end
							end
							if !found
								dw.write "#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] break\n"
								dw.flush
								break
							end
						end
					end
					#fe.write "#{Time.now.strftime('%X.%3N')} [#{$cmdline}:#{$$}] exitting debug attachment\n"
				ensure
#					$debugFileName.unlink
				end
			end
			gw.close
			$__degugWatchDogPid = gr.readline.to_i
			gr.close
			at_exit{
#				Process.kill :USR1, $__degugWatchDogPid
			}
			Process.detach pid
			fr.close
			cr.close
		end
		pinit
	end


	def p *exprs, &bl
		TZDebug.p *exprs, &bl
	end




	module Process
		class << self
			alias orgDaemon daemon
			def daemon *args
				prev = $$
				Process.orgDaemon *args
				$__orgPid__cw__.write [prev, $$].pack("S*")
				$__orgPid__cw__.flush
			end
		end
	end



	if $0 == __FILE__
		p.blue 1 + 2
		eval "
	#		p >> '~/debug2'
			p.line '#{__FILE__}', #{__LINE__}
			p.bgCyan 3 + 4, 5 + 9
			p.bgGreen
			p :red, 5 + 6
			p
		"
	end


else

	require 'Yk/path_aux'
	class TZDebug
		def initialize
		end
		def method_missing *args
			return
		end
	end
	def p *args
		return TZDebug.new
	end

end
