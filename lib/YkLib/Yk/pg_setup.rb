require 'Yk/path_aux'
require 'Yk/debug2'
require 'Yk/misc_tz'


p >> "./test.rb.debug"


require 'Yk/mojiConv'


require 'binding_of_caller'
require 'Yk/debug2'
require 'pg'
require "shellwords"

using Code


module PGSetup

module_function
def YkDBUserDir user = Etc::EUser.name
	Etc::User.home(user) / ".yk_postgres"
end

def YkDBPassword user
	(YkDBUserDir(user) / "password")._?[:_r?]&.read
end

def getPostgresPid
	%W{ps ax --cols 10000}.read_each_line_p do |ln|
		if Etc::User.uid("postgres") == "/proc/#{pid = ln.strip.split[0]}"._?[:_e?]&.stat&.uid && ln =~ /:\d\d\s+postgres\s+/
			p ln.strip.split[0]
			p pid
			return pid
		end
	end
	return nil
end

def setPostgresEnvParam
	#起動中のpostgresポート
	$pgdata, $pgport = nil
	analparam = ->{
		p _1
		_1.each_cons 2 do |a, b|
			a.gsub! /[\'\"]/, ""
			b.gsub! /[\'\"]/, ""
			p a, b
			case a
			when "-D"
				if b =~ /\//
					p.cyan
					$pgdata ||= b
				end
			when "-p"
				if b =~ /^\d+$/
					p.cyan
					$pgport ||= b
				end
			end
		end
	}
	pid = getPostgresPid
	p pid
	if pid
		analparam.("/proc/#{pid}/cmdline".read.split("\0"))
		if Process.euid == 0
			if `netstat -ltnp` =~ /\n([^\n]+)\s(#{pid})\/postgres\b/
				if $1 =~ /127.0.0.1:(\d+)/
					$pgport = $1
				end
			end
		end
	end
	#環境変数PGPORT
	$pgdata ||= ENV['PGDATA']
	$pgport ||= ENV['PGPORT']
	#servce_poolかsystemdのポート
	if !$pgdata || !$pgport
		srun = "/etc/service/postgres/run"._r?(&:read) || "/service/postgres/run"._r?(&:read)
		p srun
		sv_pool = false
		if srun
			srun.lines.select{_1 =~ /\bpostgres\b/}.each do |ln|
				analparam.(ln.strip.split)
				if ln.strip_comment.split == %W{exec /etc/service_pool/postgres}
					sv_pool = true
				end
			end
		end
		p.red
		if (!$pgdata || !$pgport) && sv_pool && "/etc/service_pool/postgres"._r?
			p.green
			"/etc/service_pool/postgres".read_each_line do |ln|
				if ln =~ /\bpostgres\b/
					analparam.(ln.strip.split)
				end
			end
		end
	end
	if !$pgdata || !$pgport
		if "/usr/bin/systemctl"._x?
			sctlRes = %W{/usr/bin/systemctl}.read_p12
			p sctlRes
			if sctlRes !~ /Failed to get D-Bus connection:/
				$pgdata ||= `systemctl show -p Environment "${SERVICE_NAME}.service" |
					sed 's/^Environment=//' | tr ' ' '\n' |
					sed -n 's/^PGDATA=//p' | tail -n 1`
				$pgport ||= `systemctl show -p Environment "${SERVICE_NAME}.service" |
					sed 's/^Environment=//' | tr ' ' '\n' |
					sed -n 's/^PGPORT=//p' | tail -n 1`
			else
				p
				%W{/usr/lib /etc}.map{_1 / "systemd/system"}.each do |d|
					p
					(d / "postgresql.service")._?[:_r?]&.then do |f|
						p
						f.read_each_line do |ln|
							case ln.strip_comment
							when /^Environment\=PGPORT\=(.*)/
								$pgport = $1.strip
								p $pgport
							when /^Environment\=PGDATA\=(.*)/
								$pgdata = $1.strip
								p $pgdata
							end
						end
					end
					if $pgport && $pgdata
						p $pgport, $pgdata
						break
					end
				end
			end
		end
	end


	if $pgport && (tmp = $pgport.strip) !~ /^\d+$/
		if tmp.empty?
			die("Empty service name specified")
		end
		require 'socket'
		begin
			p $pgport
			$pgport = Addrinfo.tcp("127.0.0.1", $pgport).ip_port
		rescue SocketError
			if $! =~ /Servname not supported/
				die("Unknown service name, '#{$pgport}' for postgres port number")
			end
		end
	end
	if !$pgdata || !$pgport
		STDERR.writeln "Cannot detect database directory and/or server port number\nPlease set environmental variable, PGDATA, PGPORT"
		return nil
	end
	if $pgdata !~ /^\//
		die("Database directory #{$pgdata} is not absolute path.")
	end
end

setPostgresEnvParam


def exec_psql user, cmd
	res = ""
	Code do |code|
		res = ""
		p.purple user, cmd#
		["psql", "-c", cmd].open "pT", user: user, chdir: :home do |t|
			pass = (Etc::User.home(user) / ".yk_postgres" / "password")._?[:_r?]&.read&.strip
			t.enter_password_if "Password: ", pass do |ln|
				res += ln
			end
		end
		if res =~ /Connection refused/ && code.first?
			p.red res
			restartPostgresDaemon
			sleep 1
			code.redo
		else
			p.purple res
			return res
		end
	end
end

def get_table_schema tName
	res = ""
	pid = nil
	%{pg_dump -t }.open "pT", pid: pid do |t|
		pass = (Etc::User.home(user) / ".yk_postgres" / "password")._?[:_r?]&.read&.strip
		t.enter_password_if "Password: ", pass do |ln|
			res += ln
		end
		begin
			while IO.select [t], [], [], 0.1
				res += t.readpartial(1000)
			end
		rescue EOFError
			break
		end
	end
	res
end

def getLocale
	%W{locale -a}.read_each_line_p do |ln|
		if ln =~ /utf8/
			return ln.strip
		end
	end
end

def createDatabase owner, dbname
	exec_psql "postgres", "CREATE DATABASE #{dbname} TEMPLATE template0 OWNER #{owner} ENCODING = 'UTF8' LC_COLLATE = '#{getLocale}' LC_CTYPE = '#{getLocale}';"
end

def tryConnection user, pw
	p.yellow user, pw
	io = IO.popen '-', "r+"
	p.yellow
	if !io
		begin
			Process.uid = Process.euid = Etc::User.id(user)
			_connectIt(user: user, password: pw)
		rescue PG::ConnectionBad
			print $!.to_s
			p.green $!
		end
		exit 0
	else
		p.yellow
		res = io.read
		p res
		case res
		when /FATAL:  password authentication failed for user \"#{Regexp.escape user}\"/
			return :passFailure
		when /role \"#{Regexp.escape user}\" does not exist/
			return :noRole
		when /fe_sendauth: no password supplied/
			return :noPassword
		when /authentication failed/
			return :passFailure
		when /FATAL:  the database system is starting up/
			sleep 1
			return tryConnection(user, pw)
		when ""
			return :success
		else
			return res
		end
	end
end

FOR_RESET_POSTGRES_PW = <<END
# "local" is for Unix domain socket connections only
local   all             all                                     peer
# IPv4 local connections:
host    all             all             127.0.0.1/32            ident
# IPv6 local connections:
host    all             all             ::1/128                 ident
END

FOR_RESET_PW = <<END
# "local" is for Unix domain socket connections only
local   all             all                                     md5
# IPv4 local connections:
host    all             all             127.0.0.1/32            md5
# IPv6 local connections:
host    all             all             ::1/128                 md5
END



def tmpConfFile user
	$access_conf_file = "#{$pgdata}/pg_hba.conf"
	begin
		$access_conf_file.cp $access_conf_file + ".org"
		($access_conf_file + ".org").chown "postgres", "postgres"
		$access_conf_file.mv $access_conf_file + ".#{Time.now.strftime('%F.%T')}"
		$access_conf_file.write user == "postgres" ? FOR_RESET_POSTGRES_PW : FOR_RESET_PW
		$access_conf_file.chown "postgres", "postgres"
		restartPostgresDaemon
		sleep 3
		yield
	ensure
		($access_conf_file + ".org").mv $access_conf_file
		restartPostgresDaemon
	end	
end


def resetPassword user, pass
	res = nil
	tmpConfFile user do
		res = exec_psql "postgres", "alter role #{user} with password '#{pass}'"
	end
	if res =~ /role.*does not exist/
		tmpConfFile user do
			res = exec_psql "postgres", "create user #{user} with password '#{pass}'"
		end
	end
	res =~ /ALTER ROLE/
end

def checkConnection user
	TTY.open do |tty|
		tty.writeln "Checking connection for user, '#{user}'"
		pwF = (Etc::User.home(user) / ".yk_postgres").check_dir / "password"
		if pwF._e?
			tty.writeln "Password file, '#{pwF}', found. Use this."
			pw = pwF.read.strip
		else
			tty.writeln "Password file, '#{pwF}', not found."
			pw = tty.prompt_password "Enter password manually: "
		end
		if !pw.empty?
			res = tryConnection user, pw
		else
			res = :emptyPassword
		end
		p.green res
		case res
		when :noRole
			pw2 = tty.prompt_password "Reenter it for confirmation: "
			if pw != pw2
				die "Inconsistent password."
			end
		when :passFailure, :noPassword, :emptyPassword
			tty.write "Authentication failed.\n" if res == :passFailure
			if tty.yn? "Reset (or create new) password."
				pw = tty.prompt_password "Enter new password (or directly enter to generate) : "
				if pw.empty?
					pw = genpassword(12)
					tty.write "Password generated.\n"
					tty.write "Select display(1) or save on '#{pwF}'(2) [1/2] ? "
					r = tty.gets
					case r.strip
					when "1"
						pwF._?[:_e?].unlink
						tty.writeln pw
					when "2"
						pwF.write pw
					else
						die("Illeagal input.")
					end
				else
					pw2 = tty.prompt_password "Reenter it for confirmation: "
					if pw != pw2
						die "Inconsistent password."
					end	
					if tty.yn? "Save the password on '#{pwF}'"
						pwF.write pw
					end
				end
				resetPassword user, pw
			else
				die
			end
		when /FATAL:  database \"(.*?)\" does not exist/
			res = createDatabase user, $1
			if res.lines[-1] =~ /^ERROR:/
				die($& + $')
			end
		when :success
			return true
		else
			die(res)
		end
	end
end

def _connectIt **opts
	dopts = {
		dbname: "yk_db_#{opts[:user] || Etc::EUser.name}", 
		user: opts[:user] || Etc::EUser.name, 
		host: '127.0.0.1', 
		port: $pgport
	}
	if dopts[:user] == "postgres"
		dopts[:dbname] = "postgres"
	end
	YkDBPassword(dopts[:user])&.then do |pw|
		dopts[:password] = pw
	end
	p.red dopts
	dopts.each do |e, ed|
		p e, ed
		dopts[e] = opts[e] || eval(%{
			p "#{e}"
			#{e}F = ("#{Etc::User.home(dopts[:user])}" / ".yk_postgres").check_dir / "#{e}"
			tmp = #{e}F._?[:_r?]&.read&.strip
			p #{e}F, tmp, "#{ed.class}", Kernel::#{ed.class}(tmp)
			# tmp = #{e}F.`._r?.read.strip
			if tmp
				Kernel::#{ed.class}(tmp)
			else
				#{ed.inspect}
			end
		})
		p.yellow
	end
	(opts.keys - dopts.keys).each do |k|
		dopts[k] = opts[k]
	end
	p caller
	p.red dopts
	begin
		conn = PG.connect(**dopts)
	rescue PG::ConnectionBad
		$!.__defun__ :opts, **dopts
		raise $!
	end
	p.yellow
	conn
end


def connectIt **opts
	begin
		_connectIt **opts
	rescue PG::ConnectionBad
		if ["localhost", "127.0.0.1", "::1/128", nil].include?($!.opts[:host])
			p.green $!.to_s
			missingSomething = Proc.new do
				if TTY.open do |tty|
					tty.writeln "Cannot connect to local server"
					if tty.yn? "Do you check the install as super user"
						[__FILE__, "check", $!.opts[:user], $!.opts[:dbname]].exec user: :root
					end
				end; else
					die($!.to_s)
				end
			end
			case $!.to_s
			when /fe_sendauth: no password supplied/
				if TTY.open do |tty|
					3.times do
						if (catch :retry do
							pw = tty.prompt_password "Password: "
							p pw
							if !pw.empty?
								begin
									p
									_connectIt password: pw
								rescue PG::ConnectionBad
									p.green $!
									if $!.to_s !~ /password authentication failed/
										die($!.to_s)
									else
										tty.write "Wrong password, "
										tty.write "retry.\n"
										throw :retry, :thrown
									end
								end
							else
								break
							end
						end) == :thrown; else
							break
						end
					end
					if tty.yn? "Do you reset password by super user"
						[__FILE__, "check", $!.opts[:user], $!.opts[:dbname]].exec user: :root
					end
				end;else
					die "no password supplied."
				end
			when /database.*does not exist/
				TTY.write $&.ln
				if TTY.yn? "Do you create as super user"
					[__FILE__, "check", $!.opts[:user], $!.opts[:dbname]].exec user: :root
				end
			when /could not connect to server: Connection refused/
				p.green "/var/run/postgresql"._d?
				if !"/var/run/postgresql"._d? || !"/usr/bin/psql"._x?
					missingSomething.call
				elsif !getPostgresPid
					STDERR.write $!.to_s
					if TTY.yn? "Do you check as super user"
						[__FILE__, "check", $!.opts[:user], $!.opts[:dbname]].exec user: :root
					end
				else
					die($!.to_s)
				end
			when /FATAL:  Ident authentication failed for user/
				missingSomething.call
			when /FATAL:  the database system is starting up/
				sleep 1
				retry
			end
			p $!
			die("For checking environment for default local database status for this script,\n  execute '#{__FILE__} check'")
		else
			raise $!
		end
	end
end

def restartPostgresDaemon
	if ! "/var/run/postgresql"._e?
		"/var/run/postgresql".mkdir
		"/var/run/postgresql".chown "postgres", "postgres"
	end
	if "/etc/service_pool/postgres"._x? && "/etc/service/postgres.list"._e?
		%W{sv postgres restart}.system
		sleep 1
	elsif "/etc/service/postgres"._d?
		"/etc/service/postgres/down".touch
		sleep 3
		"/etc/service/postgres/down".unlink
	elsif "/service/postgres"._d?
		"/service/postgres/down".touch
		sleep 3
		"/service/postgres/down".unlink
	elsif "/usr/bin/systemctl"._x? && %W{/usr/bin/systemctl status postgres}.read_p12 !~ /Failed to get D-Bus connection:|Unit postgres could not be found/
		p.yellow
		%W{systemctl restart postgres}.system
		sleep 1
	end
end

def stopPostgresDaemon
	if "/etc/service_pool/postgres"._x? && "/etc/service/postgres.list"._e?
		%W{sv postgres stop}.system
	elsif "/etc/service/postgres"._d?
		"/etc/service/postgres/down".touch
	elsif "/service/postgres"._d?
		"/service/postgres/down".touch
	elsif "/usr/bin/systemctl"._x? && %W{/usr/bin/systemctl status postgres}.read_p12 !~ /Failed to get D-Bus connection:|Unit postgres could not be found/
		%W{systemctl stop postgres}.system
	end
end

def disablePostgresDaemon
	if "/etc/service_pool/postgres"._x? && "/etc/service/postgres.list"._e?
		%W{sv postgres delete}.system
	elsif "/usr/bin/systemctl"._x? && %W{/usr/bin/systemctl status postgres}.read_p12 !~ /Failed to get D-Bus connection:|Unit postgres could not be found/
		%W{systemctl disable postgres}.system
	end
end

def deletePostgresDaemon
	"/etc/service_pool/postgres"._?[:_x?]&.then(&:unlink)
end


def modifyAuthConf
	f = "#{$pgdata}/pg_hba.conf"
	modConfLine = ""
	mod = false
	f.read_each_line do |ln|
		case ln
		when /^(local\s+all\s+all\s+)peer$/
			mod = true
			modConfLine += $1 + "md5".ln
		when /^(host\s+all\s+all\s+127.0.0.1\/32\s+)ident$/
			mod = true
			modConfLine += $1 + "md5".ln
		when /^(host\s+all\s+all\s+::1\/128\s+)ident$/
			mod = true
			modConfLine += $1 + "md5".ln
		else
			mod = true
			modConfLine += ln
		end
	end
	if mod
		f.mv f + ".bak"
		f.write modConfLine
	end
	restartPostgresDaemon
end

if __FILE__.expand_path == $0.expand_path
	case ARGV[0]
	when "check"
		if Process.euid != 0
			if TTY.open do |tty|
				p.yellow
				tty.write $!.to_s.ln
				ret = ENV['PATH'].split /:/ do |pth|
					if (pth / "pg_ctl")._e?
						tty.write "pg_ctl found in #{pth}\n"
						break :exists
					end
				end
				if ret == :exists
					tty.write "cannot connect to postgres\n"
					if tty.yn? "do you want to check environment as super user?"
						["ruby", __FILE__, "check", ARGV[0]].exec :root
					end
					tty.write "server not running\n"
					exit 1
				else
					if ARGV[2] # database not found
						if tty.yn? "Do you create now as super user"
							["ruby", __FILE__, "check", ARGV[0], ARGV[1]].exec :root
						end
					else
						tty.write "posgresql-server is not installed\n".red
						if tty.yn? "Do you install now"
							["ruby", __FILE__, "check", ARGV[0]].exec :root
						end
					end
					exit 1
				end
			end; else
				STDERR.write $!.to_s.ln
				exit 1
			end
			exit 0
		else
			retried = false

			begin
				p
				_connectIt
				p
			rescue PG::ConnectionBad
				p $!
				case $!.to_s
				when /Connection refused.*127\.0\.0\.1/m
					p
					restartPostgresDaemon
					if !retried
						retried = true
						retry
					end
				when /Ident authentication failed/
					TTY.open do |tty|
						tty.writeln "'#{$pgdata}/pg_hba.conf' has problem."
						if tty.yn? "Correnct it now"
							modifyAuthConf
						end
					end
				when /"FATAL:  the database system is starting up/
					sleep 1
					retry
				end
			end
			if "/usr/bin/rpm"._x?
				p.yellow
				doInst = false
				%W{postgresql postgresql-server postgresql-devel}.each do |pkg|
					if %W{/usr/bin/rpm -q #{pkg}}.read_p12 =~ /not installed/
						doInst = true
						break
					end
				end
				if doInst
					%W{yum -y install postgresql postgresql-server postgresql-devel}.system
				end
			elsif "/usr/bin/apt"._x?
				p.yellow
				doInst = false
				lst = %W{postgresql libpq-dev libpq-dev}
				lst.each do |pkg|
					out, err = %W{/usr/bin/dpkg -l #{pkg}}.read_12_each
					if out !~ /i*\s+#{Regexp.escape pkg}\s+/ && err =~ /dpkg\-query: no packages found matching/
						doInst = true
						break
					end
				end
				%W{apt -y install #{lst * ' '}}.system
				out, err = %W{/usr/bin/dpkg -l postgresql}.read_12_each
				ver = '\d+'
				if out =~ /i*\s+postgresql\s+(\d+)/
					ver = $1
				end
				%W{apt list}.read_each_line_p do |ln|
					if ln =~ /^(postgresql-server-dev-#{ver})\//
						%W{apt -y install #{$1}}.system
					end
				end
			end
			p.yellow
			useSystemd = nil
			if !$pgdata || !$pgport
				setPostgresEnvParam
			end
			if !$pgdata || !$pgport
				die("")
			end
			if !"#{$pgdata}/postgresql.conf"._e?
				TTY.open do |tty|
					tty.write "#{$pgdata}/postgresql.conf not found\n"
					if tty.yn? "Do you need setup database?"
						if "/usr/bin/systemctl"._x?
							ev = ENV.clone
							sctlRes = %W{/usr/bin/systemctl}.read_p12
							p sctlRes
							if sctlRes =~ /Failed to get D-Bus connection:/
								f = "/tmp/systemctl_dummy.#{$$}".check_dir / "systemctl"
								p f
								f.write <<~END
									#!/usr/bin/env ruby

									require 'Yk/path_aux'

									ARGV.each do |s|
										if s =~ /\.service$/
											"/usr/lib/systemd".recursive do |f|
												if f.basename == s
													print f.read
													exit 0
												end
											end
										end
									end
								END
								f.chmod 0777
								ev['PATH'] = f.dirname + ":" + ev['PATH']
								at_exit do
									f.dirname.rm_rf
								end
								useSystemd = false
							else
								useSystemd = true
							end
							p ev['PATH']
							res = %W{postgresql-setup initdb}.system env: ev, user: :postgres
							if !res
								die("Error: setup database failed.")
							end
						else
							useSystemd = false
						end
					else
						STDERR.write "please execute 'su posgres -c postgresql-setup initdb'\n"
						exit 1
					end
				end
			end
			p.yellow
			if !(rd = "/var/run/postgresql")._d?
				p.yellow
				rd.mkdir
				rd.chown "postgres", "postgres"
			end
			p.yellow
			if !useSystemd
				checkServiceFile = Proc.new do |f|
					if !f._e?
						f.dirname.check_dir
						p.yellow
						f.write <<~END
			#!/bin/bash

			exec su postgres -c "postgres -D #{$pgdata} -p #{$pgport}"

						END
						f.chmod 0744
					end
				end
				if "/etc/service_pool"._d? && "/usr/bin/sv"._x?
					checkServiceFile.("/etc/service_pool/postgres")
					if !"/etc/service/postgres.list"._e?
						p
						%W{sv postgres add}.system
						p
					end
					p
					%W{sv postgres start}.system
					p
					sleep 1
				elsif (d = "/service")._d? || (d = "/etc/service")._d?
					checkServiceFile.(d / "postgres/run")
				end
			end
			p.yellow
			if useSystemd
				p.yellow
				%W{systemctl enable postgres}.system
				%W{systemctl start postgres}.system
				sleep 1
			end

			p
			checkConnection "postgres"
			p
			checkConnection ARGV[1]
			p

			Code do |code|
				p.yellow
				io = IO.popen '-', "r+"
				p.yellow
				if !io
					begin
						Process.uid = Process.euid = Etc::User.id(ARGV[1])
						opt = {}
						(Etc::EUser.home / ".yk_postgres" / "password")._?[:_r?]&.then do |f|
							opt[:password] = f.read.strip
						end
						_connectIt **opt
					rescue PG::ConnectionBad
						print $!
					end
					exit 0
				else
					p.yellow
					res = io.read
					p res
					case res
					when /FATAL:  password authentication failed for user \"#{Regexp.escape ARGV[1]}\"/

					when /Ident authentication failed/
						if code.first?
							TTY.open do |tty|
								tty.writeln "'#{$pgdata}/pg_hba.conf' has problem."
								if tty.yn? "Correnct it now"
									modifyAuthConf
									code.redo
								end
							end
						else
							die($!.to_s)
						end
					when /FATAL:  database \"(.*?)\" does not exist/
						if code.first?
							if TTY.yn? "Database '#{db = $1}' does not exit.\nCreate as superuser"
								createDatabase ARGV[1], db
								code.redo
							end
						else
							die($!.to_s)
						end
					when /role \"#{Regexp.escape ARGV[1]}\" does not exist/
						if TTY.open do |tty|
							pFile = (Etc::User.home("postgres") / ".yk_postgres").check_dir / "password"
							pass = nil
							if pFile._r?
								pass = pFile.read
							else
								if tty.yn? "setting postgres password"
									p.cyan pFile
									pass = tty.setting_password(pFile)
									p.yellow
									pFile.dirname.chown_R "postgres", "postgres"
									p.green
									pFile.dirname.chmod_R 0600
								end
							end
							if pass && !pass.empty?
								pass.gsub! /'/, "\\'"
								res = nil
								["psql", "-c", "alter role postgres with password '#{pass}'"].open "pT", user: :postgres, chdir: :home do |t|
									p t
									t.enter_password_if "Password: ", pass do |ln|
										res += ln
									end
								end
								p.green res
								if !res
									abort
								end
							else
								tty.write "Please setup password for user 'postgres' in default file (#{pFile}).\n"
								exit 1
							end
							tty.write "Etc::User '#{ARGV[1]}' not registered as database user\n"
							if tty.yn? "Register '#{ARGV[1]}' ?"
								p.red
								cures = %W{createuser -h localhost -p #{$pgport} -U postgres -d -l #{ARGV[1]}}.read_p12
								p.red cures
								case cures
								when /FATAL:  Ident authentication failed for user \"postgres\"/
									modifyAuthConf
								end
								p.yellow
							end
							p.yellow
						end;else
							p.yellow
							exit 0
						end
					end
				end
				p.yellow
				break
			end
		end
		p.yellow
		exit 0
	when "uninstall"
		p ARGV
		if ARGV[1] == "--force" || TTY.yn?("uninstall postgres and yk_postgres settings")
			if Process.euid != 0
				["ruby", __FILE__, "uninstall", "--force"].exec :root
			else
				stopPostgresDaemon
				disablePostgresDaemon
				deletePostgresDaemon
				%W{rpm -e postgresql postgresql-devel postgresql-server}.system
				%W{rm -rf #{$pgdata} #{Etc::User.home("postgres")}}.system
				Etc::User.each do |u|
					(u.home / ".yk_postgres")._?[:_e?]&.rm_rf
				end
			end
		end
		exit 0
	end
end

#if !"#{$pgdata}/postgresql.conf"._e?
#	TTY.open do |tty|
#		tty.writeln "missing #{$pgdata}/postgresql.conf"
#		if tty.yn? "do you want to check environment as super user?"
#			["ruby", __FILE__, "check", Etc::EUser.name].exec :root
#		end
#	end
#end
end