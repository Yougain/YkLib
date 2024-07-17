
require 'Yk/shellquote'


if !defined? CYGWIN
	CYGWIN = (`uname` =~ /CYGWIN/)
end
if CYGWIN
	if !defined?(CYGADMIN)
		begin
			testFName = "/var/tmp/__test_admin__#{rand(10000000000)}"
			File.open testFName, "w" do |fw|
				File.chmod 0666, testFName
			end
			isAdmin = false
			begin
				require 'etc'
				File.chown Etc.getpwnam("SYSTEM").uid, Etc.getgrnam("Administrators").gid, testFName
				isAdmin = true
			rescue
			end
			CYGADMIN = isAdmin
		ensure
			File.delete testFName
		end
	end
end


if !CYGWIN
	if Process.euid != 0
		if (File.executable?(tmp = "/usr/sbin/cansudo") && system(tmp) && $? == 0 && STDIN.tty?) or File.exist?("/data/data/com.termux") or "/etc/group".read =~ /\nwheel|sudo:.*\b(#{Regexp.escape Etc.getpwuid(Process.euid).name})\b/
				exec "sudo", $0, *ARGV
		else
			exec "su",  "-c",  "#{$0} #{ARGV.condSQuote}"
		end
	end
else
	if !CYGADMIN
		if File.executable?(tmp = "/usr/bin/cygsu")
			exec "cygsu #{$0} #{ARGV.condSQuote}"
		else
			raise Exception.new("cannot execute as an administrator")
		end
	end
end


