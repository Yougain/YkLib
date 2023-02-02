
require 'binding_of_caller'
require 'Yk/debug2'


module With
	class WithClass < BasicObject
		def self.getEffectiveMethods o
			case o
			when ::Class
				parent = ::Class
			when ::Module
				parent = ::Module
			else
				parent = ::Object
			end
			o.methods - parent.instance_methods - parent.private_instance_methods
		end
		def __dup_error l
			raise ::ArgumentError.new("'#{l}' is ambiguous symbol")
		end
		def initialize w, slf, b
			@__with__ = w
			@__self__ = slf
			@__bind__ = b
		end
		List = {}
		class AmbiguousConstantSymbolReferenced < ::ArgumentError
		end
		class AmbiguousConstantSymbolReferencer < BasicObject
			def initialize label, file, lno
				@label = label
				@file = file
				@lno = lno
			end
			def method_missing *args, **hash, &prc
				raise AmbiguousConstantSymbolReferenced.new("Ambiguous constant, '#{@label}' used in #{file.basename}:#{lno} referenced")
			end
		end
	end
	
	refine Kernel do
		def with w, &prc
			b = binding.of_caller(1)
			slf = b.eval("self")
			if b.source_location[0] != "(eval)"
				c = WithClass::List[b.source_location]
				if c
					return c.new(w, slf, b).instance_eval(&prc)
				end
			end
			orgDefined = WithClass.getEffectiveMethods(slf)
			lDefined = b.local_variables
			lDefined += lDefined.map{|e| (e.to_s + "=").intern}
			toAdd = WithClass.getEffectiveMethods(w)
			dups = (orgDefined|lDefined) & toAdd
			orgs = orgDefined - toAdd - lDefined
			lcls = lDefined - toAdd
			adds = toAdd - orgDefined - lDefined
			kmths = Kernel.methods - Module.instance_methods - toAdd - orgDefined - lDefined
			c = Class.new(WithClass)
			dups.each do |l|
				c.class_eval %{
					def #{l}
						__dup_error #{l.inspect}
					end
				}
			end
			orgs.each do |l|
				c.class_eval %{
					def #{l} *args, **hsh, &prc
						@__self__.#{l} *args, **hsh, &prc
					end
				}
			end
			lcls.each do |l|
				if l.to_s[-1] != "="
					c.class_eval %{
						def #{l}
							@__bind__.local_variable_get(l)
						end
					}
				else
					c.class_eval %{
						def #{l} arg
							@__bind__.local_variable_set(l, arg)
						end
					}
				end
			end
			adds.each do |l|
				c.class_eval %{
					def #{l} *args, **hsh, &prc
						@__with__.#{l} *args, **hsh, &prc
					end
				}
			end
			main = TOPLEVEL_BINDING.eval("self")
			kmths.each do |l|
				c.define_method l do |*args, **hsh, &prc|
					main.method(l).call *args, **hsh, &prc
				end
			end
			WithClass::List[b.source_location] = c
			c.new(w, slf, b).instance_eval(&prc)
		end
	end
end

