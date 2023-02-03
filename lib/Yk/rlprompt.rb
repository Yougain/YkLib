
require 'readline.so'

class String
	def prompt (echo = true)
		if !STDIN.tty?
			raise Exception.new("cannot use #{String@prompt} when STDIN is redirected\n")
		end
		prpt = self
		aList = []
		if self.rstrip =~ /\<(.*?)\>$/
			pre = $`
			aarr = $1.split(/\|/)
			aarr.each_index do |i|
				e = aarr[i]
				case e
				when "y"
					aList.push ["y", "Yes"]
					aarr[i] = "Yes"
				when "n"
					aList.push ["n", "No"]
					aarr[i] = "No"
				when "ya"
					aList.push ["ya", "Yes to all"]
					aarr[i] = "Yes to all(ya)"
				when "na"
					aList.push ["na", "No to all"]
					aarr[i] = "No to all(na)"
				when "a"
					aList.push ["a", "All"]
					aarr[i] = "All"
				else
					if e =~ /\[(.+?)\]/
						c = $1[0].chr
						e = $` + $1 + $'
						aList.push [c, e]
					elsif e =~ /\((.+?)\)/
						c = $1[0].chr
						e = $`
						aList.push [c, e]
					else
						c = e[0].chr
						aList.push [c, e]
					end
				end
			end
			prpt = "#{pre}<#{aarr.join("|")}>"
		end
		system "stty -echo"
		begin
			res = Readline.readline(prpt)
		ensure
			system "stty echo"
		end
		if aList && aList.size >= 2
			if res == nil || (res = res.strip) == ""
				return aList[0][0]
			else
				aList.each do |e|
					e.each do |f|
						if res =~ /^#{Regexp.escape f}$/i
							return e[0]
						end
					end
				end
				return aList[0][0]
			end
		else
			return res
		end
	end
end

