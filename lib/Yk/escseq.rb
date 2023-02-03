


	module Escseq
		Colors = [ 	:black,
					:red, 
					:green, 
					:yellow, 
					:blue, 
					:purple, 
					:cyan, 
					:white,
					:unknown,
					:default
				 ]
		Colors.each_with_index do |e, i|
			col = e.to_s
			capCol = e.to_s.capitalize
			eval %{
				#{capCol} = "\\x1b[#{i + 30}m"
				Bg#{capCol} = "\\x1b[#{i + 40}m"
				def #{col}
#					if STDOUT.tty?
						#{capCol} + self + Default
#					else
#						self
#					end
				end
				def bg#{capCol}
#					if STDOUT.tty?
						Bg#{capCol} + Black + self + Default + BgDefault
#					else
#						self
#					end
				end
				def self.#{col}
#					if STDOUT.tty?
						#{capCol} + self + Default
#					else
#						self
#					end
				end
				def self.bg#{capCol}
#					if STDOUT.tty?
						Bg#{capCol} + self + Default
#					else
#						self
#					end
				end
			}
		end
		module_function
		def beIncludedBy (klass)
			klass.__send__(:include, Escseq)
		end
	end



