

require 'Yk/__hook__'

module MissingMethod
	def initialize_missing_method o, m
		@obj__ = o
		@method__ = m
	end
	def call *args, **opts, &bl
		if @method__ =~ /[^a-zA-Z0-9_?]/ && !bl && args.size <= 1 && opts.size == 0
			if args.size == 1
				eval("@obj__ #{@method__} args[0]")
			elsif args.size == 0
				eval("#{@method__} @obj__")
			end
		else
			eval("@obj__.#{@method__}(*args, **opts, &bl)")
		end
	end
	def [] *args
		call *args
	end
	def arity
		raise NotImplementedError.new("MissingMethod#arity is not implemented")
	end
	def unbind
		raise NotImplementedError.new("MissingMethod#unbound is not implemented")
	end
end


class Object
	alias_method :method_____, :method
	def method (n)
		begin
			method_____(n)
		rescue NameError
			prx = method_____(:__id__)
			prx.extend MissingMethod
			prx.initialize_missing_method self, n
			prx.__hook__ :inspect do |org|
				org.call.sub(/#[^#]+$/, "##{n}")
			end
			prx
		end
	end
end


