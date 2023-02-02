#!/usr/bin/env ruby

require "pty"
require "Yk/io_aux"
require "Yk/path_aux"
require "Yk/selector"


module TtyRewrite
	def handleIO (arr, bl)
		if bl
			begin
				t = Process.detach arr[0].pid
				t2 = Thread.new do
					t.join
					arr[0].close
					if arr[0].respond_to? :selectors
						arr[0].selectors.each do |s|
							s.int
						end
					end
				end
				ret = bl.call *arr
				t2.join
				ret = !$?.exitstatus ? nil : $?.exitstatus == 0
			ensure
				arr.each do |e|
					e.closed? || e.close
				end
			end
			ret
		else
			arr
		end
	end
	def pty_spawn3 (*args, &bl)
		mio = nil
		args.delete_if do |s|
			if s.is_a? IO
				mio = s
				true
			else
				false
			end
		end
		#if !mio.tty? || (CYGWIN || "/dev/" + `ps -p #{$$} -o tty`.split[1] != "/proc/#{$$}/fd/#{mio.to_i}".readlink)
		#	mio = nil
		#else
			stty = `stty -g`
		#end
		fp, slave = PTY.open
		if fp
			Exception.new("cannot allocate pseudo tty")
		end
		pid = fork do
			Process.setsid
			#Process.setpgrp
			fq = File.open pty.slave, "rw"
			fq.reopen fqFile
			if mio
				fq.attr = mio.attr
				fq.winsz = mio.winsz
			end
			STDIN.reopen fq
			STDOUT.reopen fq
			STDERR.reopen fq
			if stty
				system "stty #{stty}"
			end
			fq.close
			fp.close
			exec *args
		end
		trap :WINCH do
			fp.winsz = STDIN.winsz
			Process.kill :WINCH, pid
		end
		fp.__defun__ :pid, pid
		handleIO [fp], bl
	end
	module_function :handleIO, :pty_spawn3
end

		#STDIN.set_raw do
		#	t1 = fp.transfer_to STDOUT
		#	t2 = STDIN.transfer_to fp
		#	t1.join
		#	t2.join
		#end

# trap SIGWINCH ?ƃV?O?i???̓]???B

class String
	def tty_rewrite &bl
		[self].tty_rewrite &bl
	end
end


class Array
	def tty_rewrite
		TtyRewrite.pty_spawn3 STDIN, *self do |fp|
			STDIN.set_raw do
				Selector.select do |s|
					s.at_read STDIN do |buff|
						buff == "" && closing = true
						yield buff, "r", fp.pid
						s.reserve_write fp, buff
						if closing
							s.reserve_write fp, nil
						end
					end
					s.at_read fp do |buff|
						buff == "" && closing = true
						yield buff, "w", fp.pid
						s.reserve_write STDOUT, buff
						if closing
							s.reserve_write STDOUT, nil
						end
					end
				end
			end
		end
	end
end


if __FILE__.expand_path == $0.expand_path
	def main
		ARGV.tty_rewrite do |buff, mode|
			case mode
			when "r"
				
			when "w"
				
			end
		end
	end
	main
end


