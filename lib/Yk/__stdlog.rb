#!/usr/bin/env ruby

require 'tempfile'
require 'syslog'
require 'Yk/file_aux'
require 'Yk/__defun__'


module Syslog
	alias :org_open :open
	def open
		if !Syslog.opened?
			Syslog.org_open
		end
	end
	module_function :open, :org_open
end


Syslog.open



class Stdlog
	stdoutLog = true
	stdoutDrt = true
	UseConsole = !ENV['STDLOG_NO_CONSOLE']
	if ENV['STDLOG_STDOUT_NOT_TTY'] || !STDOUT.tty?
		ENV['STDLOG_STDOUT_NOT_TTY'] = "1"
		if ENV['STDLOG_NO_CONSOLE']
			stdoutLog = true
			stdoutDrt = false
		else
			stdoutLog = false
			stdoutDrt = true
		end
	end
	StdoutLog = stdoutLog
	StdoutDrt = stdoutDrt
	def Stdlog.stdlogFunc
		ENV["STDLOG_FUNC"]
	end
	def Stdlog.errlogFunc
		ENV["ERRLOG_FUNC"]
	end
	class Piper
		attr :fw
		def initialize (&bl)
			@fr, @fw = IO.pipe
			init_pid = $$.to_s
			@fr.sync = true
			closed = false
			r = rand.to_s[2..-1]
			t = Thread.new do
				Thread.pass
				@fr.each_line do |ln|
					if ln != "#{r}\n"
						bl.call ln
					else
						@fr.close
						break
					end
				end
			end
			@finalizer = Proc.new do |mode|
				if init_pid == $$.to_s && !closed
					closed = true
					@fw.write "#{r}\n"
					if mode != true
						@fr.each_line do |ln|
							if ln == "#{r}\n"
								break
							end
							bl.call ln
						end
					end
				end
			end
			ObjectSpace.define_finalizer t, @finalizer
		end
		
		
		def close
			@finalizer.call true
			@fw.close
		end

	end
	
	class Pipeback < Piper
		attr :org
		def initialize (fd, drt = nil)
			drt ||= fd.dup
			@org = fd.dup
			prc = Proc.new do |ln|
				yield ln, drt
			end
			super &prc
			fd.reopen fw
			fd.__defun__ :direct do
				drt
			end
			fd.__defun__ :restore do
				fd.reopen @org
			end
			@org
		end
	end

	class Bypass < Piper
		def initialize (evsym, out)
			prc = Proc.new do |ln|
				out.write ln
			end
			super &prc
			ENV[evsym] = fw.fileno.to_s
		end
	end
	
	def Stdlog.prefix (prog = "", str = "")
		require 'Yk/misc_tz'
		progStr = (@@prefixProgs + [prog]).cond_join(":", "(parent = {})")
		nameStr = (@@prefixNames + [str]).prefix_cond_join(":")
		[progStr, nameStr].prefix_cond_join(" ")
	end

	def Stdlog.logerr (arg)
		arg = arg.chomp
		arg = arg.gsub /\n/, " "
		arg = arg.gsub /\t/, " "
		if errlogFunc
			i = 0
			cur = arg[i ... i + 80]
			while true
				if i != 0
					body = "(__debug__errlog__) " + cur
				else
					body = "(__debug__errlog__) (__d_first)" + cur
				end
				i += 80
				cur = arg[i ... i + 80]
				if cur
					tail = "(__d_cont)\n"
					Syslog.err body + tail
				else
					tail = "\n"
					Syslog.err body + tail
					break
				end
			end
		else
			Syslog.err arg
		end
	end

	def Stdlog.main
		psf, psf = "", ""
		if ENV['STDLOG_PARENT'] != nil && ENV['STDLOG_PARENT'] =~ /::/
			pre = $`
			post = $'
			if pre && pre != ""
				@@prefixNames = pre.split /:/
			else
				@@prefixNames = []
			end
			if post && post != ""
				@@prefixProgs = post.split /:/
			else
				@@prefixProgs = []
			end
		else
			@@prefixNames = []
			@@prefixProgs = []
		end
		if ENV['RUBYOPT'] == nil || ENV['RUBYOPT'] !~ /(^|\s)\-rtz\/__stdlog\.rb\b/
			ENV['RUBYOPT'] = (ENV['RUBYOPT'] || "") + " -rtz/__stdlog.rb "
			Pipeback.new STDOUT do |ln1, direct1|
				direct1.write ln1 if StdoutDrt
				Syslog.info prefix + ln1 if StdoutLog && stdlogFunc
			end
			@@stdoutm = Bypass.new('STDLOG_STDOUT_DIRECT', STDOUT.direct).fw
			Pipeback.new STDERR do |ln2, direct2|
				direct2.write ln2 if UseConsole
				logerr prefix + ln2
			end
			@@stderrm = Bypass.new('STDLOG_STDERR_DIRECT', STDERR.direct).fw
		else
			if !defined? @@stdoutm
				@@stdoutm = (IO.open(ENV['STDLOG_STDOUT_DIRECT'].to_i) rescue return)
			end
			if !defined? @@stderrm
				@@stderrm = (IO.open(ENV['STDLOG_STDERR_DIRECT'].to_i) rescue return)
			end
			Pipeback.new STDOUT, @@stdoutm do |ln3, direct3|
				direct3.write ln3 if StdoutDrt
				Syslog.info prefix + ln3 if StdoutLog && stdlogFunc
			end
			Pipeback.new STDERR, @@stderrm do |ln4, direct4|
				direct4.write ln4 if UseConsole
				logerr prefix + ln4
			end
		end

	end
end

Stdlog.main

alias :org_fork :fork
alias :org_exec :exec

def ___setParent (prc, prefix = nil)
	if ENV['STDLOG_PARENT'] && ENV['STDLOG_PARENT'] =~ /::/
		pre, post = $`, $'
		parents =  (post != "" && post != nil) ? post.split(/:/) : []
		prefixes = (pre != "" && pre != nil) ? pre.split(/:/) : []
	else
		prefixes = []
		parents = []
	end
	parents.push "#{$0}[#{prc.to_s}]"
	if prefix != nil && prefix.strip != ""
		prefixes.unshift prefix
	end
	ENV['STDLOG_PARENT'] = prefixes.join(":") + "::" + parents.join(":")
end

def fork
	parent = $$.to_s
	if block_given?
		ret = org_fork do
			___setParent parent
			Stdlog.main
			yield
		end
		ret
	else
		ret = org_fork
		if ret == nil
			___setParent parent
			Stdlog.main
		end
		ret
	end
end

alias :system_org :system
def system (*args)
	all_prefix = ""
	apx = ""
	if String === args[0]
		if args[0] =~ /^prefix:/
			all_prefix = $'.strip
			apx = all_prefix + ": "
			args.shift
		end
	end
	child_prefix = nil
	piper1 = Stdlog::Piper.new do |ln|
		while child_prefix == nil
			sleep 0.1
		end
		STDOUT.direct.write ln if Stdlog::StdoutDrt
		Syslog.info Stdlog.prefix + child_prefix + apx + ln if Stdlog::StdoutLog&& Stdlog::stdlogFunc
	end
	piper2 = Stdlog::Piper.new do |ln|
		while child_prefix == nil
			sleep 0.1
		end
		STDERR.direct.write ln if Stdlog::UseConsole
		Stdlog.logerr(Stdlog.prefix + child_prefix + apx + ln)
	end
	parent = $$.to_s
	pid = org_fork do
		STDOUT.reopen piper1.fw
		STDERR.reopen piper2.fw
		___setParent parent, all_prefix
		if !exec *args
			exit 1
		end
	end
	if Array === args[0]
		child_prefix = args[0][0] + "[#{pid}]: "
	else
		child_prefix = args[0].strip.split(/\s+/)[0] + "[#{pid}]: "
	end
	ret = Process.waitpid2(pid)[1].exitstatus == 0
	piper1.close
	piper2.close
	ret
end


def exec (*args)
	STDERR.flush
	STDOUT.flush
	if STDERR.respond_to? :restore
		STDERR.restore
	end
	if STDOUT.respond_to? :restore
		STDOUT.restore
	end
	org_exec *args
end


if File.basename($0) == File.basename(__FILE__)
	2.times do
		STDERR.write "err\n"
	end
	2.times do
		STDOUT.write "out\n"
	end
	p "aa"
	system "prefix: test", "ruby -e 'STDOUT.write(\"testout\\n\"); STDERR.write(\"testerr\\n\");'"
	system "prefix: test2", "echo stdout; echo $RUBYOPT >&2"

	def pp

		sdddfags
	end
	def xd
		pp
	end
	xd
	sleep 10
end


