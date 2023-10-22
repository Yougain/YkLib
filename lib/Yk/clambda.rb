#!/usr/bin/env ruby


require 'Yk/misc_tz'


module TZLambda

	class Base
	    instance_methods.each { |m|
			if m.to_s !~ /^__/ && m.to_s != "object_id"
		        undef_method m
			end
	    }
		def __l_to_lambda__
			self
		end
	    def method_missing (name, *args, &bl)
	    	MethodElem.new nil, self, name, *args, &bl
		end
		def hasTheme?
			false
		end
		def call *cargs
			if !hasTeme?
				__call nil, *cargs
			else
				__call *cargs
			end
		end
	end

	class PlaceHolder < Base
	    def initialize pos
	    	@pos = pos
	    end
		def __call *cargs
			cargs[@pos]
		end
		def coerce a
			[self, a]
		end
		def hasTheme?
			@pos == 0
		end
	end


	class MethodElem < Base
		def initialize bnd, target, name, *args, &bl
			@binding = bnd
			@target = target.__l_to_lambda__
			@args = []
			args.each do |a|
				@args.push a.__l_to_lambda__
			end
			@block = bl
			@name = name
		end
		def __call *cargs
			args = @args.map{ |e| e.__call(*cargs)}
			if !@binding
				t = @target.__call(*cargs)
				m = t.__send__(@name, *args, &bl)
			else
				args = args.map{|e| "ObjectSpace._id2ref(#{e.__id__})"}
				if @block
					args.push "&ObjectSpace._id2ref(#{@block.__id__})"
				end
				@binding.eval("#{@name} #{args.join(', ')}")
			end
		end
		def hasTheme?
			return true if @target.hasTheme?
			@args.each do |a|
				return true if a.hasTheme?
			end
		end
		def to_proc
			Proc.new do |*args|
				__call nil, *args
			end
		end
	end


	class FixedElem < Base
		def initialize obj
			@obj = obj
		end
		def __call *cargs
			return @obj
		end
	end


	class NullElem
	    instance_methods.each { |m|
			if m.to_s !~ /^__/ && m.to_s != "object_id"
		        undef_method m
			end
	    }
		def initialize bnd
			@binding = bnd
		end
	    def method_missing (name, *args, &bl)
    		MethodElem.new @binding, nil, name, *args, &bl
		end
	end

	PlaceHolder0 = PlaceHolder.new 0
	PlaceHolder1 = PlaceHolder.new 1
	PlaceHolder2 = PlaceHolder.new 2
	PlaceHolder3 = PlaceHolder.new 3
	PlaceHolder4 = PlaceHolder.new 4
	PlaceHolder5 = PlaceHolder.new 5
	PlaceHolder6 = PlaceHolder.new 6
	PlaceHolder7 = PlaceHolder.new 7
	PlaceHolder8 = PlaceHolder.new 8
	PlaceHolder9 = PlaceHolder.new 9
	PlaceHolder10 = PlaceHolder.new 10
	PlaceHolder11 = PlaceHolder.new 11
	PlaceHolder12 = PlaceHolder.new 12
	PlaceHolder13 = PlaceHolder.new 13
	PlaceHolder14 = PlaceHolder.new 14
	PlaceHolder15 = PlaceHolder.new 15
	PlaceHolder16 = PlaceHolder.new 16
	PlaceHolder17 = PlaceHolder.new 17
	PlaceHolder18 = PlaceHolder.new 18
	PlaceHolder19 = PlaceHolder.new 19
	PlaceHolder20 = PlaceHolder.new 20

	class MethodCall
	    instance_methods.each { |m|
			if m.to_s !~ /^__/ && m.to_s != "object_id"
		        undef_method m
			end
	    }
	    def initialize bnd, obj, mode
	    	@binding = bnd
	    	@mode = mode
	    	@obj = obj
	    end
		def method_missing name, *args, &bl
			name = @mode + name.to_s
			@binding.eval(name).__send__(:__call, @obj, *args, &bl)
		end
	end

	class CallBlock
	    instance_methods.each { |m|
			if m.to_s !~ /^__/ && m.to_s != "object_id"
		        undef_method m
			end
	    }
	    def initialize bnd, obj, rflag = false
	    	@binding = bnd
	    	@obj = obj
	    	@rflag = rflag
	    end
		def method_missing name, *args
			bl = args.pop
			if @obj
				res = @obj.__send__(name, *args, &bl)
				if @rflag
					@obj.replace res
				else
					res
				end
			else
				args._!.map{|e| "ObjectSpace._id2ref(#{e.__id__})"}
				args.push "&ObjectSpace._id2ref(#{bl.to_proc.__id__})"
				res = @binding.eval("#{name} #{args.join(', ')}")
				if @rflag
					@binding.eval("replace ObjectSpace._id2ref(#{res.__id__})")
				else
					res
				end
			end
		end
	end
	class SetTheme
		def initialize obj, *lexprs
			@lexprs = lexprs
			@obj = obj
		end
		def call *cargs
			ret = @lexprs.map{|e| e.__call @obj, *cargs}
			if ret.size == 1
				ret[0]
			else
				ret
			end
		end
	end

end


def __ *args
	case args.size
	when 0
		return unless bnd = caller_binding
		TZLambda::NullElem.new bnd
	when 1
		args[0].__l_to_lambda__
	else
		args = args.map do |a|
			a.__l_to_lambda__
		end
		args.__l_to_lambda__
	end
end



class Object
	def __l_to_lambda__
		TZLambda::FixedElem.new self
	end
	def _I *lexprs
		return unless bnd = caller_binding
		obj = bnd.eval("self") == self ? nil : self
		if lexprs.size == 0
			TZLambda::MethodCall.new bnd, obj, ""
		else
			TZLambda::SetTheme.new obj, *lexprs
		end
	end
	[[:a, ?@], [:d, ?$]].each do |s, m|
		class_eval %{
			def _I#{s.to_s}
				return unless bnd = caller_binding
				obj = bnd.eval("self") == self ? nil : self
				TZLambda::MethodCall.new bnd, obj, #{m.inspect}.chr
			end
		}
	end
	[["!", ", :replace"], ["", ""]].each do |s, f|
		class_eval %{
			def _L#{s}
				return unless bnd = caller_binding
				obj = bnd.eval("self") == self ? nil : self
				TZLambda::CallBlock.new bnd, obj#{f}
			end
		}
	end
end


0.upto 20 do |i|
	eval %{
		def __#{i}
			return TZLambda::PlaceHolder#{i}
		end
	}
end


class String
	alias :__plus__ :+
	def + (other)
		return __(self) + other if other.is_a?(TZLambda::Base)
		__plus__ other
 	end
end


if $0 == __FILE__
	def fold &m
		[100, 200, 300].inject{|a, e| m.call(a, e) }
	end
	def test a, b
		[a + 1, b + 1]
	end
	require 'Yk/path_aux'
	require 'Yk/debug2'
	p 3
	p
	a = "#{ENV['HOME']}/.console_files"
	p
	b = __1 * __1 * __2
	p
	p __I.b 2, 3
	p "Q"._?._e?.inspect
	p "asdf"._e?
	clause __.a + __0 + __1._?._e?.__it.to_s do |c|
		p "test"._I(c, c).call "asdf"
	end
	e = __FILE__
	clause _0.expand_path.write_la _1.ln do |c|
		p c
		"~/.command_arg_files.test"._I.c e
		if e._d? || e._!.dirname._d?
			"~/.command_arg_dirs.test"._I.c e
		end
	end
	a = [1, 2, 3]
	p a
	a._L!.map(100 + _1)
	p a
	p _L.fold(:+)
	a = __.test __1, __2
	p _I.a 5, 6
	p _I(a, a).call 7, 8
	p [?a, ?b, ?c]._L!.map("Z" + _1)
end


