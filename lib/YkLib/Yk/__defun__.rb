
class Object
	def __defun__ (name, *sargs, **sopts, &sbl)
		(class << self;self;end).instance_eval do
			if sbl
				define_method name do |*args, **opts, &bl|
					sbl.call *(sargs + args), **(sopts.merge opts), &bl
				end
			elsif sopts.empty?
				if sargs.empty?
					define_method name do
						nil
					end
				elsif sargs.size == 1
					define_method name do
						sargs[0]
					end
				else
					define_method name do
						sargs
					end
				end
			else
				if sargs.empty?
					define_method name do
						sopts
					end
				else
					define_method name do
						sargs + [sopts]
					end
				end
			end
		end
		self
	end
	def __undefun__ (name)
		(class << self;self;end).instance_eval do
			remove_method name
		end
		self
	end
end

