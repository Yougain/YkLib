

require 'resolv'
require 'Yk/__hook__'
require 'thread'
require 'Yk/set'
require 'etc'
require 'fileutils'


class Resolv
	RESOLVA = "#{Etc.getpwuid(Process.euid).dir}/.resolva"
	if !File.exist? RESOLVA
		Dir.mkdir RESOLVA
	end
	RESOLVA_D = "#{RESOLVA}/names"
	if !File.exist? RESOLVA_D
		Dir.mkdir RESOLVA_D
	end
	RESOLVA_N = "#{RESOLVA}/no_name"
	class << Object.new
		Resolv.__hook__ :getaddresses do |org|
			mutex = Mutex.new
			prc = Proc.new do |a, f|
				lastMTime = File.mtime(f) rescue Time.at(0)
				set = Set.new
				if File.directory?(f)
					Dir.foreach f do |ent|
						next if ent == ".." || ent == "."
						if File.mtime("#{f}/#{ent}") > Time.now - 3600 * 24
							set.insert ent
						else
							File.delete "#{f}/#{ent}"
						end
					end
				end
				if lastMTime < Time.now - 180
					trials = 0
					mtrials = 0
					ttrials = 0
					newIPSet = Set.new
					while mutex.synchronize{trials <= set.size * 3 && mtrials < 30 && ttrials < 100}
						t = Thread.new do
							Thread.pass
							res = []
							begin
								ttrials += 1
								res = org.getaddresses a
								ttrials = 0
							rescue Exception
							end
							mutex.synchronize do
								newIPSet.insert *res
								set.insert *res
								trials += res.size
								mtrials += 1
							end
						end
						sleep 0.1
					end
					mutex.synchronize do
						if !File.directory? f
							Dir.mkdir f
						end
						newIPSet.each do |ip|
							FileUtils.touch "#{f}/#{ip}"
						end
					end
					FileUtils.touch f
				end
				set.to_a
			end
			nr = prc.call "asdf.aa#{rand.to_s[2..-1]}aa.com", RESOLVA_N
			if org.args.size > 0
				r = prc.call org.args[0], "#{RESOLVA_D}/#{org.args[0]}"
				r -= nr
			else
				nr
			end
		end
		Resolv.__hook__ :getaddress do |org|
			rs = org.call
			Resolv.getaddresses.include?(rs) ? nil : rs
		end
	end
end


