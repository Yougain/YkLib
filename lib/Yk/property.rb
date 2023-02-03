if RUBY_VERSION >= '2.7'

require 'Yk/eval_alt'


	module Friend
		FriendList = Hash.new{|h, k| h[k] = Set.new}
		refine Module do
			def friend *args
				binding.of_caller(1).eval("self").class_eval %Q{
					private
					if !Friend::FriendList.key? self
						[#{args.join(', ')}].each do |e|
							Friend::FriendList[self].add e
						end
						def __allow_call? name
							if [private_methods, protected_methods].find{_1.include?(name)}
								cls = binding.of_caller(2).eval("self.class")
								if !self.is_a?(Class)
									toFind = Friend::FriendList[self.class]
								else
									k = Friend::FriendList.keys.find{|e| self.is_a?(e)}
									toFind = Friend::FriendList[k] if k
								end
								found = toFind&.find{|e|
									c = cls
									ret = while c && c != Class
										if e == c
											break true
										end
										c = c.superclass
									end
									ret
								}
							end
							found
						end
						alias_method :__method_missing_org, :method_missing
						def method_missing name, *args, **h, &bl
#							p.red args, h, bl
							if __allow_call? name
								method(name).call *args, **h, &bl
							else
								__method_missing_org name, *args, **h, &bl
							end
						end
						alias_method :respond_to_missing_org, :respond_to_missing?
						def respond_to_missing? symbol, include_private
							__allow_call?(symbol) || respond_to_missing_org(symbol, include_private)
						end
						def self.friend *clsList
							clsList.each{Friend::FriendList[self].add _1}
#							p FriendList
						end
					end
				}
#				p FriendList
			end
		end
	end
	module Misc
		refine Module do
			def refine_class cls, &prc
				c = class << cls; self; end
				refine c, &prc
			end	
		end
	end
end


module Warning
	def self.warn (msg, category: nil)
		if msg !~ /redefining Object\#(method_missing|respond_to_missing\?) may cause infinite loop/
			super(msg)
		end
	end
end


module Proc_
	class Proc_from_LocalVariable < Proc
		def initialize b, l
			@binding = b
			@label = l
			super()do
				_
			end
		end
		def _ &bl
			ret = @binding.local_variable_get(@label)
			if bl
				instance_eval(&bl)
			end
			ret
		end
		def _= arg
			@binding.local_variable_set(@label, arg)
		end
		def pivot
			@binding.local_variable_get(@label)
		end
		def pivot= arg
			@binding.local_variable_set(@label, arg)
		end
	end
	class Proc_from_MethodLabel < Proc
		def initialize obj, label, *args, **opts, &bl
			@label = label
			@args = args
			@opts = opts
			@block = bl
			@obj = obj
			super do |*args, **opts, &bl|
				_ *args, **opts, &bl
			end
		end
		def _ *args, **opts, &bl
			@obj.method(@label).call(*(@args + args), **(@opts.merge opts), &(bl || @block))
		end
		# _{1 < a <= b < 3 <= 5}
		# _.foo(_{1 or 2})._
		# _.foo(_{arr})._
		# _.a
		# _.a{pivot += 1}
		def _= *args, **opts, &bl
			@eqLabel ||= (@label.to_s + "=").intern
			@obj.method(@eqLabel).call(*(@args + args), **(@opts.merge opts), &(bl || @block))
		end
		def pivot *args, **opts, &bl
			ret = self._(*args, **opts, &bl)
			method(:_=).call(*args, **opts, &bl)
			ret
		end
	end
	class Proc_seed < BasicObject
		def method_missing label, *args, **opts, &bl
			if @binding && args.empty? && opts.empty? && !bl && @binding.local_variable_defined?(label)
				Proc_from_LocalVariable.new @binding, label do; end
			else
				Proc_from_MethodLabel.new @obj, label, *args, **opts, &bl
			end
		end
		def initialize obj, b = nil
			@obj = obj
			@binding = b
		end
	end
	refine Object do
		private
		def _
			Proc_seed.new(self, binding.of_caller(1))
		end
		alias_method :__org_method_missing, :method_missing
		def method_missing label, *args, **opts, &bl
			if label == :_ #public call
				Proc_seed.new(self)
			else
				__org_method_missing(label, *args, **opts, &bl)
			end
		end
		alias_method :__org_respond_to_missing?, :respond_to_missing?
		def respond_to_missing? label, priv
			if label == :_
				true
			else
				__org_respond_to_missing?(label, priv)
			end
		end
	end
	class Proc_from_Label < Proc
		def initialize label, args, opts, bl
			super do |obj|
				obj.method(label).call(*args, **opts, &bl)
			end
		end
	end
	refine Symbol do
		def call *args, **opts, &bl
			Proc_from_Label.new self, args, opts, bl
		end
	end
end

module Property
	class BObject
		Methods = %W{
			__send__
			__id__
			instance_eval
			method_missing
			p
			pp
			binding
			object_id
			initialize
			respond_to?
			caller
			inspect
		}
		instance_methods.each do |m|
			alias_method ("__call_org_method_of_#{m}_on_BObject__").intern, m
			if !Methods.include? m.to_s
				remove_method(m) rescue nil
			end
		end
		private_instance_methods.each do |m|
			alias_method ("__call_org_method_of_#{m}_on_BObject__").intern, m
			if !Methods.include? m.to_s
				remove_method(m) rescue nil
			end
		end
		def __call_org_method__ label, *args, **opts, &bl
			__send__ ("__call_org_method_of_" + label.to_s + "_on_BObject__").intern, *args, **opts, &bl
		end
	end
	%W{start placeHolder get set pivot swap this}.each do |name|
		Property.module_eval %{
			module_function
			def #{name}
				@@#{name}
			end
			def #{name}= sym
				@@#{name} = sym
			end
		}
	end
	def property_public_methods
		%W{get set pivot swap}
	end
	module_function :property_public_methods
end

CompChain.seed = [:___, :■, :͐ , :͑ , :͔ , :͕  ]

# 1 < ■2 == ■3 < 4

Property.start = [:_, :▲, :̄  ]
Property.placeHolder = [:__, :∆, :͝ , :ˬ, "➀➁➂➃➄➅➆➇➈", :͟  ]

#_①:͝is_a? ,

#case 
#when ˬ_e?
#when ˬis_a?(Foo)
#when s̄in(➀) == 1.0
#end

Property.get = [:_get, :▼]
Property.set = [:_set, :◀]
Property.pivot = [:_pivot, :◀◀]
Property.swap = [:_swap, :◀▶]
Property.this = :_

# 

module Property
	class Property_base < BObject
		def coerce a
			if !Property_base.(a)
				ag = Property_raw.new(a)
			else
				ag = a
			end
			[ag, self]
		end
		alias_method :__org_method_missing, :method_missing
		MCheck = {}
		def method_missing label, *args, **opts, &bl
			curCall = nil
			begin
				if caller(1)[0] =~ /:/
					curCall = caller(1)[0]
					if curCall[/^(.*):/, 1] == __FILE__
						return __org_method_missing(label, *args, **opts, &bl)
					elsif (require "fiber"; MCheck[Fiber.current] ||= {})[[curCall, label]]
						MCheck[Fiber.current].delete [curCall, label]
						return __org_method_missing(label, *args, **opts, &bl)
					else
						MCheck[Fiber.current][[curCall, label]] = true
					end
				end
				Property_from_MethodLabelBase.emerge self, label, *args, **opts, &bl
			ensure
				(MCheck[Fiber.current] ||= {}).delete([curCall, label]) if curCall
			end
		end
		def respond_to_missing? label, priv
			true
		end
		def === caseArg
			if caseArg.respond_to?(:__call_org_method__) && caseArg.__call_org_method__(:is_a?, Property_base)
				caseArg.__Property_get__ __Property_get__
			else
				__Property_get__ caseArg
			end
		end
		def to_proc
			Proc.new do |*args, **opts, &bl|
				__Property_get__ *args, **opts, &bl
			end
		end
		Property.property_public_methods.each do |m|
			pm = "__Property_#{m}__".intern
			define_method pm do |*args, **opts, &bl|
				__org_method_missing pm, *args, **opts, &bl
			end
			mm = Property.method(m.intern).()
			if pm != mm
				class_eval %{
					def #{mm} (...)
						#{pm}(...)
					end
				}
			end
		end
		class_eval %{
			def #{Property.this} (...)
				__Property_get__(...)
			end
			def #{Property.this}= (...)
				__Property_set__(...)
			end
		}
		def __Property_pivot__ *args, &bl
			ret = __Property_get__
			__Property_set__ *args, &bl
			ret
		end
		def __Property_this__= *args
			__Property_set__ *args
			__Property_get__
		end
		def __Property_swap__ b
			if !b.respond_to?(:__call_org_method__) || !b.__call_org_method__(:is_a?, Property_base)
				raise ArgumentError.new("#{b.inspect} is not a property")
			end
			tmp = __Property_get__
			__Property_set__ b.__Property_get__
			b.__Property_set__ tmp
			[__Property_get__, b.__Property_get__]
		end
	end
	class Property_from_Constant < Property_base
		def initialize b, l
			@binding = b
			@label = l
		end
		def __Property_get__ (...)
			@binding.eval(@label)
		end
	end
	class Property_from_LocalVariable < Property_base
		def initialize b, l
			@binding = b
			@label = l
		end
		def __Property_get__ (...)
			@binding.local_variable_get(@label)
		end
		def __Property_set__ *args, &bl
			if !args.empty?
				if !bl
					@binding.local_variable_set @label, (args.size == 1 ? args[0] : args)
				else
					raise ArgumentError("Called with both arguments and block.")
				end
			else
				if bl
					tmp = @binding.local_variable_get @label
					@binding.local_variable_set @label, bl.call(tmp)
				else
					raise ArgumentError("Called without arguments nor block")
				end
			end
		end
	end
	class Property_from_LocalVariableSetter < Property_base
		def initialize b, l, *args
			@binding = b
			@label = l
			@args = ags
		end
		def __Property_get__ (...)
			if @args.size == 1
				@binding.local_variable_set(@label, @args[0])
			elsif @args.size >= 2
				@binding.local_variable_set(@label, @args)
			end
		end
	end
	class Property_raw < Property_base
		def initialize obj
			@obj = obj
		end
		def __Property_get__ (...)
			if @obj.respond_to?(:__call_org_method__) && @obj.__call_org_method__(:is_a?, Property_base)
				@obj.__Property_get__(...)
			else
				@obj
			end
		end
	end
	#case _(:@obj).__call_org_method__(:is_a?, __1)
	#when __1.Property_callArgProvider
	# ...
	#end
	#case Property_callArgProvider
	#when _(:@obj).__call_org_method__(:is_a?, __1)
	# ...
	#end
	class Property_from_MethodLabelBase < Property_base
		DoEval = %{
			noa = ->o{
				case o.size
				when 0
					nil
				when 1
					o[0]
				else
					o
				end
			}
			if @obj.respond_to?(:__call_org_method__) && (
				if @obj.__call_org_method__(:is_a?, Property::Property_callArgProvider)
					obj = noa.(@obj.__Property_get__(*args, **opts, &block))
				elsif @obj.__call_org_method__(:is_a?, Property::Property_base)
					obj = @obj.__Property_get__(*args, **opts, &block)
				end)
			else
				obj = @obj
			end
		}.l
		DoEvalAll = %{
			#{DoEval.l}
			eargs = []
			@args.each{|e| 
				if e.respond_to?(:__call_org_method__) && (
					if e.__call_org_method__(:is_a?, Property::Property_callArgProvider_to_a)
						p
						eargs.push *e.__Property_get__(*args, **opts, &block)
					elsif e.__call_org_method__(:is_a?, Property::Property_callArgProvider)
						p eargs
						eargs.push *e.__Property_get__(*args, **opts, &block)
						p eargs
					elsif e.__call_org_method__(:is_a?, Property::Property_base)
						p
						eargs.push e.__Property_get__(*args, **opts, &block)
					end)
				else
					eargs.push e
				end
			}
			if @opts
				eopts = {}
				@opts.each do |k, v|
					if k.respond_to?(:__call_org_method__) && k.__call_org_method__(:is_a?, Property_callArgProvider_to_hash) && v == nil
						eopts.merge k.__Property_get__(*args, **opts, &block)
					else
						if v.respond_to?(:__call_org_method__)
							if v.__call_org_method__(:is_a?, Property::Property_callArgProvider)
								vc = noa.(v.__Property_get__(*args, **opts, &block))
							elsif v.__call_org_method__(:is_a?, Property::Property_base)
								vc = v.__Property_get__(*args, **opts, &block)
							end
						end
						vc ||=  v
						if k.respond_to?(:__call_org_method__)
							if k.__call_org_method__(:is_a?, Property::Property_callArgProvider)
								kc = noa.(k.__Property_get__(*args, **opts, &block))
							elsif k.__call_org_method__(:is_a?, Property::Property_base)
								kc = k.__Property_get__(*args, **opts, &block)
							end
						end
						kc ||=  k
						eopts[kc] = vc
					end
				end
			end
			if @block
				if @block.respond_to?(:__call_org_method__) && (
					if @block.__call_org_method__(:is_a?, Property::Property_callArgProvider_to_proc)
						eblock = @block.__Property_get__(*args, **opts, &block)
					elsif @block.__call_org_method__(:is_a?, Property::Property_callArgProvider)
						eblock = noa.(@block.__Property_get__(*args, **opts, &block))
					elsif @block.__call_org_method__(:is_a?, Property::Property_base)
						eblock = @block.__Property_get__(*args, **opts, &block)
					end)
				else
					eblock = @block
				end
			end
		}.l
		def self.emerge obj, label, *args, **opts, &bl
			if label == :[] && !bl
				Property_from_SubscriptGetterMethodLabel.new obj, *args, **opts
			elsif args.empty? && opts.empty? && !bl && label[-1] != "="
				Property_from_GetterMethodLabel.new obj, label
			else
				Property_from_MethodLabel.new obj, label, *args, **opts, &bl
			end
		end
	end
	class Property_from_MethodLabel < Property_from_MethodLabelBase
		def initialize obj, label, *args, **opts, &bl
			@label = label
			@args = args
			@opts = opts
			@block = bl
			@obj = obj
		end
		x = %{
			def __Property_get__ (*args, **opts, &block)
				p args
				#{DoEvalAll.l}
				p eargs
				obj.method(@label).call(*eargs, **eopts, &eblock)
			end
		}.l
		class_eval x
	end
	class Property_from_MethodLabel_PropertyBase < Property_from_MethodLabelBase
		def __Property_set__ args, bl
			if !args.empty?
				if bl
					raise ArgumentError.new("Cannot use both arguments and block")
				else
					yield *args
				end
			else
				if bl
					yield instance_eval(&bl)
				else
					raise ArgumentError.new("Cannot use both arguments and block")
				end
			end
		end
	end
	class Property_from_GetterMethodLabel < Property_from_MethodLabel_PropertyBase
		def initialize obj, label
			@label = label
			@obj = obj
		end
		class_eval %{
			def __Property_get__ *args, **opts, &block
				#{DoEval.l}
				obj.method(@label).call
			end
			def __Property_set__ *args, **opts, &block
				@eqLabel ||= (@label.to_s + "=").intern
				#{DoEval.l}
				super args, block do |*eargs|
					obj.method(@eqLabel).call(*eargs)
				end
			end
		}.l
	end
	class Property_from_SubscriptGetterMethodLabel < Property_from_MethodLabel_PropertyBase
		def initialize obj, *args, **opts
			@obj = obj
			@args = args
			@opts = opts
		end
		class_eval %{
			def __Property_get__ *args, **opts, &block
				#{DoEvalAll.l}
				obj.[](*eargs, **eopts)
			end
			def __Property_set__ *args, **opts, &block
				#{DoEvalAll.l}
				p eargs
				p args
				p eopts
				p block
				if !args.empty?
					if !block
						obj.[]=(*eargs, *args, **eopts)
						return
					end
				elsif block
					op = block.call(obj.[](*eargs, **eopts))
					p op
					obj.[]=(*eargs, op, **eopts)
					return
				end
				raise ArgumentError.new("operand missing or too many operands")
			end
		}.l
	end

	class Property_seed < BObject
		def method_missing label, *args, **opts, &bl
			ret = nil
			if label[-1] != "="
				if args.empty? && opts.empty? && !bl
					if @binding.local_variable_defined?(label)
						ret = Property_from_LocalVariable.new(@binding, label)
					elsif @binding.eval("Module.constants").include?(label)
						ret = Property_from_Constant.new(@binding, label)
					end
				end
				ret ||= Property_from_MethodLabelBase.emerge @obj, label, *args, **opts, &bl
			else
				labelPre = label.to_s.chop.intern
				if args.empty? && opts.empty? && bl
					if @binding.local_variable_defined?(labelPre)
						ret = Property_from_LocalVariableSetter.new(@binding, labelPre, *args)
					elsif @binding.eval("Module.constants").include?(labelPre)
						raise ArgumentError.new("Cannot reinitialize constant")
					end
				end
				ret ||= Property_from_MethodLabelBase.emerge @obj, label, *args
			end
			ret
		end
		def respond_to_missing? label, priv
			true
		end
		def initialize obj, b = nil
			@obj = obj
			@binding = b
		end
	end
	class Prperty_seed_unboundMethod < Property_seed
		def method_missing label, *args, **opts, &bl
			Property_from_MethodLabelBase.new Property_callArgProvider.new(1), label, *args, **opts, &bl
		end
		def initialize
		end
		def to_a
			Property_callArgProvider_to_a.new
		end
		def to_hash
			Property_callArgProvider_to_hash.new
		end
		def to_proc
			Property_callArgProvider_to_proc.new
		end
	end
	class Property_callArgProvider < Property_base
		def initialize *args
			@arg_indexes = []
			@opt_list = []
			@all_opts = false
			@add_block = false
			@all = false
			p args
			args.each do |e|
				case e
				when Integer
					if e >= 1
						@arg_indexes.push e - 1
					else
						@arg_indexes.push e
					end
				when Symbol, String
					case e.to_s
					when /^\d+$/
						i = e.to_s.to_i
						if i >= 1
							i -= 1
						end
						@arg_indexes.push i
					when "**"
						@all_opts = true
					when "*"
						@arg_indexes.push :all
					when "&"
						@add_block = true
					when "..."
						@arg_indexes.push :all
						@all_opts = true
						@add_block = true
					else
						e = e.to_sym
						@opt_list.push e if !@opt_list.index(e)
					end
				end
			end
		end
		def __Property_get__ *args, **opts, &bl
			rargs = []
			rbl = bl if @add_block
			p @arg_indexes, args
			@arg_indexes.each do |e|
				if e == :all
					if !rargs.empty?
						rargs.push *args
					end
				elsif e >= 0
					rargs.push args[e] if e < args.size
				else
					rargs.push args[e] if e >= -args.size
				end
			end
			p rargs
			if @all_opts
				ropts = opts
			else
				ropts = {}
				@opt_list.each do |k|
					if opts.key? k
						ropts[k] = opts[k]
					end
				end
			end
			ret = []
			ret += rargs
			p ret
			ret.push ropts if !ropts.empty?
			ret.push rbl if rbl
			p ropts
			p rbl
			p ret
			ret
		end
		def to_a
			[Property_callArgProvider_to_a.new(self)]
		end
		def to_hash
			{Property_callArgProvider_to_hash.new(self) => nil}
		end
		def to_proc
			Property_callArgProvider_to_proc.new(self)
		end
	end
	module Property_callArgProvider_to 
		def initialize provider
			@provider = provider
		end
	end
	class Property_callArgProvider_to_a < Property_base
		def Property_callArgProvider_to_a;end
		include Property_callArgProvider_to
		def __Property_get__ *args, **opts, &bl
			@provider.__Property_get__ *args, **opts, &bl
		end
	end
	class Property_callArgProvider_to_hash < Property_base
		def Property_callArgProvider_to_hash;end
		include Property_callArgProvider_to
		def __Property_get__ *args, **opts, &bl
			r = @provider.__Property_get__ *args, **opts, &bl
			if !r.empty? && r[0].is_a?(Hash) && !r[0].empty?
				r[0]
			else
				{}
			end
		end
	end
	class Property_callArgProvider_to_proc < Proc
		def Property_callArgProvider_to_proc;end
		def initialize provider
			@provider = provider
			super do;end
		end
		def __Property_get__ *args, **opts, &bl
			r = @provider.__Property_get__ &bl
			if !r.empty? && r[0].is_a?(Proc)
				r[0]
			else
				nil
			end
		end
	end
	refine Kernel do
		# x = _.a[1]
		# x._ += 1
		# x.get
		# x.set(100)
		# x.set{_ + 100}
		# x.pivot(100)
		# x.pivot{_ + 100}
		# call(_.a + _{0 or 1} + c)
		module_function
		module_eval %{
			module_function
			def #{Property.start} arg = nil
				if !arg
					Property::Property_seed.new(self, binding.of_caller(1))
				else
					case arg.respond_to?(:ruby_symbol) && arg.ruby_symbol
					when :class_variable
						Property::Property_from_ClassVariable.new(b, self)
					when :instance_variable
						Property::Property_from_InstanceVariable.new(b, self)
					when :capitalized_symbol
						if b.eval("Module.constants").include?(self)
							Property::Property_from_Constant.new(b, self)
						else
							Property::Property_from_MethodLabelBase.emerge b.eval("self"), self
						end
					when :non_capitalized_symbol
						if b.local_variable_defined?(self)
							Property::Property_from_LocalVariable.new(b, self)
						else
							Property::Property_from_MethodLabelBase.emerge b.eval("self"), self
						end
					else
						raise ArgumentError("\#{arg}.inspect is not a symbol or not a compatible symbol to ruby")
					end
				end
			end
			module_function
			def #{Property.placeHolder} *args
				if args.empty?
					Property::Prperty_seed_unboundMethod.new
				else
					Property::Property_callArgProvider.new *args
				end
			end
			1.upto 9 do |i|
				module_eval %{
					module_function
					def #{Property.placeHolder}\#{i}
						Property::Property_callArgProvider.new \#{i}
					end
				}
			end
		}.l
	# (_.a(__(1)) * __(:a) * __('...')).foo &__(:&))
	end
	refine Symbol do
		class RubySymbol
			def ruby_symbol sym
				case sym.to_s
				when /^\@\@/
					if (self.class.class_variable_set(sym, 1) rescue nil)
						return :class_variable
					end
				when /^\@/
					if (instance_variable_set(sym, 1) rescue nil)
						return :instance_variable
					end
				else
					if (self.class.const_defined?(sym) || (self.class.const_set(sym, 1)) rescue nil)
						return :capitalized_symbol
					end
					if (binding.local_variable_set(sym) rescue nil)
						return :non_capitalized_symbol
					end
				end
				nil
			end
			TestSymbol = self.new
			def self.ruby_symbol sym
				TestSymbol.ruby_symbol sym
			end
		end
		def self.ruby_symbol sym
			RubySymbol.ruby_symbol sym
		end
		def self.for_ruby_local_variable?
			ruby_symbol == :non_capitalized_symbol
		end
		def self.for_ruby_constant?
			ruby_symbol == :capitalized_symbol
		end
	end
end



