


require 'Yk/path_aux'
require 'etc'
require 'Yk/rpm-packageproxy.rb'
require 'Yk/procinfo'


class UPRepos
	def self.rpmbuild spec, progName = nil
		resFiles = []
		ENV["LANG"] = "C"
		%W{rpmbuild -ba #{spec}}.read_each_line_p12 do |ln|
			print ln
			case ln
			when /^Wrote: (\/usr\/src\/redhat\/RPMS\/[^\/]+\/.+\.rpm)\b/
				resFiles.push $1
			when /^Wrote: (\/usr\/src\/redhat\/SRPMS\/.+\.rpm)\b/
				resFiles.push $1
			end
		end
		if $?.exitstatus != 0
			return false
		end
		update progName, *resFiles
	end
	def self.update progName, *resFiles
		if resFiles.size == 0
			return false
		end
		if resFiles[-1] !~ /\.rpm$/
			progName = resFiles.pop
		end
		if !(duserFile = "/etc/rpb".check_dir / "default_user").readable_file?
			"/home".each_entry do |d|
				if (d / "rpb/ARCHIVES").directory?
					u = nil
					begin
						u = Etc.getpwuid(d.stat.uid).name
					rescue ArgumentError
					end
					if u
						duserFile.write u
					end
				end
			end
		end
		uname, home = nil, nil
		begin
			u = duserFile.read.strip_comment
			uname, home = (pw = Etc.getpwnam(u)).name, pw.dir
		rescue ArgumentError
			raise Exception.new("user, #{u} has been not found")
		end
		resFiles.each do |f|
			if f =~ /\.src\.rpm$/
				(home / "rpb/ARCHIVES/OTHERS/SRPMS").update_rpm f
			else
				(home / "rpb/ARCHIVES/OTHERS/RPMS").update_rpm f
			end
		end
		parInfo = nil
		if !progName || !(parInfo = ProcInfo.findParent(progName))
			if "uprepos".system
				true
			else
				false
			end
		else
			cCount = 0
			parInfo.children.each do |pe|
				cCount += 1 if pe.exe.dirname.dirname == $0.expand_path.dirname.dirname && pe.pid != Process.pid
			end
			if cCount > 0
				return true
			else
				fork do
					ProcInfo.current.close_files
					STDIN.reopen "/dev/null"
					STDERR.reopen "/dev/null"
					STDOUT.reopen "/dev/null", "w"
					while parInfo.alive?
						sleep 1
					end
					"uprepos".exec
				end
			end
		end
		true
	end
end


