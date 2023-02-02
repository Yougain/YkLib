#!/usr/bin/env ruby

require 'Yk/path_aux'

"tty_width.dat.rb".open "w" do |w|
	first = true
	i = 0
	"tty_width_available".read_each_line do |ln|
		u, v = ln.split
		if !first
			if i % 5 == 0
				w.write ",\n\t\t"
			else
				w.write ", "
			end
		else
			w.write "\t\t"
		end
		first = false
		w.write "[0x#{sprintf("%04x", u.to_i(16))}, #{sprintf("%2s", v)}]"
		i += 1
	end
end

