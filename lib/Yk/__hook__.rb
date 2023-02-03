#


require 'Yk/misc_tz'


class Object
	def __reraise_method_missing (name)
		ex = NameError.new("undefined local variable or method `#{name}' for #{self}")
		begin
			raise ex
		rescue NameError => e
			bt = e.backtrace
			bt.each_index do |i|
				i = bt.size - i - 1
				if bt[i] =~ /in \`method_missing\'/
					bt.slice!(0..i)
					break
				end
			end
			raise
		end
	end
end


class Hook
	class EachHook
		instance_methods.each do |e|
			if !["__id__", "__send__", "object_id"].include? e.to_s
				undef_method e
			end
		end
		def initialize (hook, c)
			@hook = hook
			@closure = c
			(class << self; self; end).class_eval %{
				#undef_method :initialize
				def #{c.label} (*args, **opts, &bl)
					newClosure = Hook::Closure.new(@closure.obj, :#{c.label}, bl, args, opts)
					if @hook
						@hook.call EachHook.new(@hook.prev, newClosure)
					else
						newClosure.call_org
					end
				end
				def method_missing (name, *args, **opts, &bl)
					obj.instance_eval do
						__send__(name, *args, **opts, &bl)
					end
				end
			}
		end
		def call
			if @hook
				@hook.call EachHook.new(@hook.prev, @closure)
			else
				@closure.call_org
			end
		end
		def args
			@closure.args
		end
		def args= (ags)
			@closure.args = (ags)
		end
		def obj
			@closure.obj
		end
		def obj= (o)
			@closure.obj = o
		end
		def label
			@closure.label
		end
		def label= (l)
			@closure.label = l
		end
		def block
			@closure.block
		end
		def block= (b)
			@closure.block = b
		end
		def opts
			@closure.opts
		end
		def opts= (o)
			@closure.opts = o
		end
	end
	attr_reader :body
	attr :nxt, true
	attr :prev, true
	attr :label
	HookList = Hash.new { |h, k| h[k] = Hash.new }
	def initialize (obj, label, *largs, **lopts, &bd)
		if [:initialize, :__hook__, :call, :args, :block, :obj, :opts, :label].find { |e| e.to_s == label.to_s || "#{e.to_s}=" == label.to_s }
			raise ArgumentError.new("cannot hook `initialize', `hook', `call', `args', `obj', `label'")
		end
		@obj = obj
		@label = label
		@body = bd
		@local_args = largs
		@local_opts = lopts
		if !HookList[obj].key? label
			(class << obj; self; end).class_eval do
				if method_defined? label
					alias_method "__hk_org_#{label.to_s.underscore_escape}", label
				else
					if label != :method_missing
						eval %{
							def __hk_org_#{label.to_s.underscore_escape} (*args, **opts, &bl)
							end
						}
					else
						eval %{
							def __hk_org_#{label.to_s.underscore_escape} (*args, **opts, &bl)
								#__reraise_method_missing args[0]
								#self.class.superclass.instance_method(label).bind(self).call(*args, **opts, &bl)
								super
							end
						}
					end
				end
				eval %{
					def #{label} (*args, **opts, &bl)
						if tmp = HookList[self][:#{label}]
							tmp.createEachHook(self, :#{label}, bl, args, opts).call
						else
							#if :#{label} == :read and args[-1].is_a?(Hash)
							#		__hk_org_#{label.to_s.underscore_escape}(*args[0..-2], **args[-1], &bl)
							#else
								__hk_org_#{label.to_s.underscore_escape}(*args, **opts, &bl)
							#end
						end
					end
				}
			end
		end
		@prev = HookList[obj][label]
		HookList[obj][label] = self
		if @prev
			@prev.nxt = self
		end
	end
	def remove
		@prev.nxt = @next if @prev
		@nxt.prev = @prev if @nxt
		if HookList[@obj][@label] == self
			HookList[@obj][@label] = @prev
		end
		@nxt = nil
		@prev = nil
	end
	def call (prevEachHook)
		@body.call prevEachHook, *@local_args, **@local_opts
	end
	class Closure
		attr_accessor :obj, :label, :block, :args, :opts
		def initialize (o, l, b, a, op)
			@obj, @label, @block, @args, @opts = o, l, b, a, op
		end
		def call
			@obj.method(@label).call(*@args, **@opts, &@block)
		end
		def call_org
			@obj.method("__hk_org_#{@label.to_s.underscore_escape}").call(*@args, **@opts, &@block)
		end
	end
	def createEachHook *all_args
		if all_args[0].is_a? Closure
			c = all_args[0]
		else
			c = Closure.new(*all_args)
		end
		EachHook.new(self, c)
	end
	class OrgProxy
		instance_methods.each do |e|
			if !["__id__", "__send__", "object_id"].include? e.to_s
				undef_method e
			end
		end
		def initialize (o)
			@obj = o
			(class << self; self; end).class_eval do
				#undef_method :initialize
			end
		end
	end
	def self.createOrgProxy (*objs)
		proxyList = []
		objs.each do |obj|
			proxy = OrgProxy.new(obj)
			HookList[self].each_value do |hook|
				lb = hook.label.to_s.underscore_escape
				proxy.__defun__ "__org_hook_#{lb}", hook
				(class << proxy; self; end).class_eval %{
					def #{hook.label} (*args, **opts, &bl)
						hk = __org_hook_#{lb}.createEachHook(@obj, :#{hook.label}, bl, args, opts)
						hk.call
					end
				}
			end
			(class << proxy; self; end).class_eval %{
				def method_missing (name, *args, **opts, &bl)
					@obj.instance_eval do
						if respond_to?(tmp = "__hk_org_" +name.to_s.underscore_escape)
							method(tmp).call(*args, **opts, &bl)
						else
							method(name).call(*args, **opts, &bl)
						end
					end
				end
			}
			proxyList.push proxy
		end
		proxyList
	end
end


class Object
	def __hook__ (label, *local_args, **local_opts, &bd)
		Hook.new(self, label, *local_args, **local_opts, &bd)
	end
	def __hook_group (*objList)
		if objList.size == 0
			ret = *Hook.createOrgProxy(self)
		else
			ret = *Hook.createOrgProxy(*objList)
		end
		if block_given?
			yield ret
		else
			ret
		end
	end
end




