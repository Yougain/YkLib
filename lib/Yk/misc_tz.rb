#!/usr/bin/env ruby

#require 'continuation'
require 'binding_of_caller'

YK_MODULE_HOOK = Hash.new{|h, k| h[k] = []}

def if_class mname, &bl
	if Kernel.const_defined?(mname)
		Kernel.const_get(mname).module_eval &bl
	else
		YK_MODULE_HOOK[mname].push bl
	end
end

def if_module mname, &bl
	if_class mname, &bl
end

module Kernel
	__seed__ = rand(10000000000)
	eval %{
		alias __require__#{__seed__} require
		def require *to_require
			get_defs = ->{YK_MODULE_HOOK.each_key.select{::Kernel::const_defined?(_1)}}
			pre = get_defs[]
			__require__#{__seed__} *to_require
			(get_defs[] - pre).each do |smod|
				YK_MODULE_HOOK[smod].each do |bl|
					Kernel.const_get(smod).module_eval &bl
				end
			end
		end
	}
end


def die msg = nil
	if msg
		STDERR.write msg.chomp.ln
	end
	exit 1
end

def btrace
	ret = nil
	begin
		raise 'dummy'
	rescue
		ret = $!.backtrace
	end
	ret.shift
	ret.shift
	ret.each do |e|
		e.sub! /(.*):(\d+).*/ do
			$1.basename + ":" + $2
		end
	end
	lst = nil
	ret2 = []
	ret.each do |e|
		e =~ /:(\d+)/
		if $` != lst
			lst = $`
			ret2.push e
		else
			ret2[-1] += "," + $1
		end
	end
	ret2
end

 
TopLevelMethod = Object.new
class << TopLevelMethod
	instance_methods.each { |m|
		if !["object_id", "__send__", "__id__"].include? m.to_s
			undef_method m
		end
	}
	def method_missing (name, *args, **opts, &bl)
		p.bgRed TopLevelMethod
		TOPLEVEL_BINDING.eval("self").__send__(name, *args, **opts, &bl)
	end
	def respond_to? name, include_all = false
		TOPLEVEL_BINDING.eval("self").respond_to? name, true
	end
end


def parse_caller(at)
  if /^(.+?):(\d+)(?::in `(.*)')?/ =~ at
    file = $1
    line = $2.to_i
    method = $3
    [file, line, method]
  end
end



def caller_binding
    return binding.of_caller(2)
  cc = nil     # must be present to work within lambda
##  cpos = parse_caller(caller.first)
  count = 0    # counter of returns
##  traceArr = []

   ret = callcc do |cont|
		cc = cont
		nil
	end

  if !ret
	  set_trace_func lambda { |event, file, lineno, id, binding, klass|
##   	 traceArr.push [event, file, lineno, count, cc, id, klass, eval("self.class", binding)]
    # First return gets to the caller of this method
    # (which already know its own binding).
    # Second return gets to the caller of the caller.
    # That's we want!
    if count == 2
      set_trace_func nil
      # Will return the binding to the callcc below
      if cc == nil
##			STDERR.write [cpos, traceArr].inspect.ln
##			STDERR.flush
			Process.kill :TERM, Process.pid
			sleep 1000
		end
      cc.call binding
	    elsif event == "return"
   	   count += 1
	    end
  	}
	end
  # First time it'll set the cc and return nil to the caller.
  # So it's important to the caller to return again
  # if it gets nil, then we get the second return.
  # Second time it'll return the binding.
##	traceArr.push [cc, ret]
	return ret
end


def assign_it label, value
	return unless bnd = caller_binding
	old_id = bnd.eval(label.to_s).__id__
	new_id = value.__id__
	bnd.eval("#{label.to_s} = ObjectSpace._id2ref(#{new_id})")
	begin
		yield ObjectSpace._id2ref(old_id)
	ensure
		bnd.eval("#{label.to_s} = ObjectSpace._id2ref(#{old_id})")
	end
end


class Object
	def significant?
		true
	end
end

class NQObject
    instance_methods.each { |m|
		if !["__id__", "__send__", "object_id"].include? m.to_s
	        undef_method m
		end
    }
    def method_missing (name, *args, &bl)
        self
    end
    def initialize
    end
    def nil?
        true
    end
	def __it
		return nil
	end
	def respond_to? m
		m == :__isNQObject__?
	end
	def coerce a
		[self, a]
	end
	Obj = NQObject.new
end


class Object
	if !method_defined? :then
		def then &prc
			if !nil?
				prc.call self
			end
		end
	end
    def _? &prc
		if self == TopLevelSelf
			return unless bnd = caller_binding
		end
		if !prc
			QObject.new bnd || self
		else
			if res = prc.call(self)
				if res.is_a?(Label)
					if method(res).call
						self
					else
						nil
					end
				else
					self
				end
			else
				nil
			end
		end
    end
    def _! &prc
		if self == TopLevelSelf
			return unless bnd = caller_binding
		end
		if !prc
			QObject.new bnd || self, false
		else
			if !prc.call(self)
				self
			else
				nil
			end
		end
    end
    def __not?
    	QObject.new self, false
    end
	def __and?
		self
	end
	def __it &bl
		if bl		
			bl.call self
		else 
			self
		end
	end
	if !method_defined? :tap
		def tap
			yield self
			self
		end
	end
end

def __topl____
	self
end
TopLevelSelf = __topl____


def nil._?
	return NQObject.new
end

def nil.__and?
	return NQObject.new
end

def false._?
	return NQObject.new
end

def false.__and?
	return NQObject.new
end




class QObject
    instance_methods.each { |m|
		if !["__id__", "__send__", "object_id"].include? m.to_s
	        undef_method m
		end
    }
    def initialize obj, mode = true
    	@mode = mode
        @obj = obj
    end
	 def __obj
		@obj
	end
    def method_missing (name, *args, **opts, &bl)
    	if @obj != nil
    		hasQObj = false
			qobj = nil
			args.each_with_index do |e, i|
				case e
				when QObject
					hasQObj = true
					args[i] = e.__obj
					qobj = e.__obj
				when NQObject
					return NQObject::Obj
				end
			end
			if @obj.is_a? Binding
				args = args.map{|e| "ObjectSpace._id2ref(#{e.__id__})"}
				if bl
					args.push "&ObjectSpace._id2ref(#{bl.__id__})"
				end
				res = @obj.eval("#{name} #{args.join(', ')}")
			else
				res = @obj.__send__(name, *args, &bl)
			end
			if hasQObj
				return qobj
			else
		        res = res ? true : false
	        	if res ^ !@mode
	        		@obj
	        	else
	        		NQObject::Obj
	        	end
	        end
		else
			NQObject::Obj
		end
	end
	def respond_to? name, include_all = false
		true
	end
	def [] (label)
		if @obj.method(label).call ^ !@mode
			@obj
		else
			nil
		end
	end
end





class Numeric
  def roundup(d=0)
    x = 10**d
    if self > 0
      (self * x).ceil.quo(x)
    else
      (self * x).floor.quo(x)
    end
  end

  def rounddown(d=0)
    x = 10**d
    if self < 0
      (self * x).ceil.quo(x)
    else
      (self * x).floor.quo(x)
    end
  end

  def roundoff(d=0)
    x = 10**d
    if self < 0
      (self * x - 0.5).ceil.quo(x)
    else
      (self * x + 0.5).floor.quo(x)
    end
  end
end


class Integer
	def kill arg = :TERM
		Process.kill arg, self
	end
	def waitpid
		Process.waitpid self
	end
end

class Array
	def kill arg = :TERM
		if self.size > 0
			Process.kill arg, *self
		end
	end
end

def clause *args
	yield *args
end


module Code
	refine Kernel do
		class Code__
			def first?
				cur = (@clause_variables ||= {})[caller(1)]
				if cur != :first_passed
					@clause_variables[caller(1)] = :first_passed
					if block_given?
						yield
					else
						true
					end
				else
					nil
				end
			end
			def redo
				throw @symbol, :redo
			end
			def break
				throw @symbol, :break
			end
			def to_proc
				@proc
			end
			def to_sym
				@symbol ||= inspect.to_sym
			end
			def initialize &bl
				@proc = bl
			end
		end
		def Code
			c = Code__.new
			loop do
				case catch(c.to_sym){yield c}
				when :redo
					redo
				when :break
					break
				end
				break
			end
		end
	end
end


if !defined? CYGWIN
	CYGWIN = (`/bin/uname` =~ /CYGWIN/)
end
if CYGWIN
	if !defined?(CYGADMIN)
		testFName = "/var/tmp/__test_admin__#{rand(10000000000)}"
		begin
			File.open testFName, "w" do |fw|
				File.chmod 0666, testFName
			end
			isAdmin = false
			begin
				require 'etc'
				File.chown Etc.getpwnam("SYSTEM").uid, Etc.getgrnam("Administrators").gid, testFName
				isAdmin = true
			rescue
			end
			CYGADMIN = isAdmin
		ensure
			File.delete testFName
		end
	end
end


class Reexception < Exception
	def initialize
		@reexception = $!
	end
	def reraise
		$! = @reexception
		raise
	end
end

 
class String
    #def -@
     #   first = false
     #   findent = nil
     #   ret = ""
     #   self.each_line do |e|
     #       if e == "\n" && !findent
     #           next
     #       end
     #       if !findent
     #           e =~ /^\s+/
     #           findent = ($& || "")
     #       end
     #       if e =~ /^#{Regexp.escape findent}/
     #           ret += $'
     #       else
     #           ret += e
     #       end
     #   end
     #   if ret[-1] != ?\n && ret =~ /[\t ]+$/
     #       ret = $` 
     #   end
     #   ret
    #end
    def first_line
    	if self =~ /\n/
    		$`
    	else
    		self
    	end
    end
    def first_section
    	i = self.index("\n\n")
    	if i
    		self[0..i]
    	else
    		self
    	end
    end
	def significant?
		strip != ""
	end
end


def nil.significant?
	false
end

class Array
	def significant?
		!empty?
	end
end

class Integer
	def significant?
		self != 0
	end
end


require 'digest/md5'

class String
	def md5sum
		Digest::MD5.hexdigest(self)
	end
end


class String
	def refeed
		if self[-1] != ?\n
			self + "\n"
		else
			self
		end
	end
end

begin
require 'sync'


class FreeFormatCoHash
  include Sync_m rescue nil
	class Item
		attr :lastUsed
		def initialize (index, parent)
			@index = index
			@props = Hash.new
			@parent = parent
			@lastUsed = Time.now
		end
		def method_missing (name, *args)
			@lastUsed = Time.now
			if name.to_s[-1] == ?=
				tmp = name.to_s.chop
				@props[tmp] ||= args[0]
				@parent.propList(tmp)[args[0]] = self
				@props[tmp]
			else
				@props[name.to_s]
			end
		end
		def respond_to_missing? name, include_private
			if name.to_s[-1] == ?=
				true
			else
				if @props[name.to_s]
					true
				else
					false
				end
			end
		end
		def del
			@props.each do |k, v|
				@parent.propList(k).delete v
			end
		end
	end
	def initialize
		super
		@propList = Hash.new
		@list = Hash.new
	end
	def [] (index)
		synchronize do
			@list[index] ||= Item.new(index, self)
			item = @list[index]
		end
	end
	def delete (key)
		synchronize do
			@list[key].del
			@list.delete key
		end
	end
	def propList (propName)
		synchronize do
			@propList[propName] ||= Hash.new
		end
	end
	def method_missing (name, *args)
		synchronize do
			if name.to_s[-1] == ?=
				raise Exception.new("cannot use method #{name}\n")
			end
			@propList[name.to_s]
		end
	end
	def respond_to_missing? name, include_private
		if @propList[name.to_s]
			true
		else
			false
		end
	end
end
rescue Exception
end


class Array
	def prefix_join (sep, capsule = nil)
		ret = ""
		each do |e|
			ret += e + sep
		end
		if ret != "" && capsule != nil
			ret = capsule.split(/\{\}/).join(ret)
		end
		ret
	end
	def prefix_cond_join (sep, capsule = nil)
		ret = ""
		each do |e|
			if e != nil && e.strip != ""
				ret += e.strip + sep
			end
		end
		if ret != "" && capsule != nil
			ret = capsule.split(/\{\}/).join(ret)
		end
		ret
	end
	def cond_join (sep = " ", capsule = nil)
		ret = ""
		arr = []
		each do |e|
			if e != nil && e.strip != ""
				arr.push e.strip
			end
		end
		ret = arr.join(sep)
		if ret != "" && capsule != nil
			ret = capsule.split(/\{\}/).join(ret)
		end
		ret
	end
	def each2 hasLast = false
		(0 ... size / 2).each do |i|
			yield self[i * 2], self[i * 2 + 1]
		end
		if hasLast && size % 2 == 1
			yield self[-1], nil
		end
	end
	def each2by1
		(0 ... size - 1).each do |i|
			yield self[i], self[i + 1]
		end
	end
end


class AnonStruct
	@@astructs = {}
	def AnonStruct.[] (hash)
		hk = hash.keys
		if !(as = @@astructs[hk])
			@@astructs[hk] = as = Class.new(Array)
			hk.each_index do |i|
				as.instance_eval %{
					define_method :#{hk[i]} do
						self[#{i}]
					end
					define_method :#{hk[i]}= do |arg|
						self[#{i}] = arg
					end
				}
			end
			args = hk.map{ |e| e.to_s }.join(", ")
			as.instance_eval %{
				define_method :initialize do |#{args}|
					super()
					push #{args}
				end
			}
		end
		as.new(*hash.values)
	end
end


module UnderscoreEscaper
	CHAR_w = "abcdefghijklmnopqrstuvwxyzABCDEFGHI"
	CHAR_W = ' !"#$%&\'()*+,-./:;<=>?@[\\]^_{|}~^?'
	module_function
	def esc_table (c)
    	CHAR_w[CHAR_W.index(c)].chr
	end
	def unesc_table (c)
    	CHAR_W[CHAR_w.index(c)].chr
	end
	def escape (arg)
		if arg == nil
			"_Z_"
		else
    		arg.gsub /_|\W/ do |e|
        		"_" + esc_table(e) + "_"
	    	end
	    end
	end
	def unescape (arg)
		if arg == "_Z_"
			nil
		else
	    	arg.gsub /_(\w)_/ do
	        	unesc_table($1)
		    end
		end
	end
end


class CommandLine
	class Opt
		attr :toShort
		attr :argNum
		attr :name
		attr :redirectOpts
		def initialize (n, s, an, ro = nil)
			@name = n
			@toShort = s
			@argNum = an
			@redirectOpts = ro
		end
		def isRedirector?
			@argNum == -1
		end
		def isShort?
			@name.size == 2
		end
		def isLong?
			!isShort?
		end
		def Opt.createOpt (exp, agNum, redirectOpts = nil)
			ret = []
			if !exp || exp.size == 0
				return []
			end
			hasDefault = false
			if exp =~ /\[\?\]$/
				exp = $`
				hasDefault = true
				if agNum != 1
					raise Exception.new("cannot use default argument for option, #{exp}")
				end
			end
			arr = exp.split /,/
			toShort = nil
			arr.each do |expr|
				lopt = nil
				sopt = nil
				if expr =~ /\((.)\)/
					sopt = $1
					if $` && $`.strip != ""
						lopt = $`
					elsif $' && $'.strip != ""
						lopt = $'
					end
				elsif expr =~ /\[(.)\]/
					sopt = $1
					tlopt = ""
					if $` && $`.strip != ""
						tlopt = $`
					end
					tlopt += $1
					if $' && $'.strip != ""
						tlopt += $'
					end
					if tlopt != ""
						lopt = tlopt
					end
				elsif expr.size == 1
					sopt = expr
					lopt = nil
				else
					sopt = nil
					lopt = expr
				end
				lopt = nil if lopt == ""
				sopt = nil if sopt == ""
				if sopt
					toShort ||= "-" + sopt[0].chr
					sopt.each_byte do |c|
						ret.push Opt.new("-" + c.chr, toShort, agNum, redirectOpts)
					end
				end
				if lopt
					if !toShort
						if sopt
							toShort = "-" + sopt[0].chr
						else
							toShort = "--" + lopt
						end
					end
					if hasDefault
						ret.push Opt.new("--" + lopt, toShort, -1, redirectOpts)
					else
						ret.push Opt.new("--" + lopt, toShort, agNum, redirectOpts)
					end
				end
			end
			ret
		end
	end
	class Error < ArgumentError
	end
	def getOptList (noArgOpts, oneArgOpts, twoArgOpts, redirector)
		require "Yk/set"
		ret = KeyedSet.new :name
		[[noArgOpts, 0], [oneArgOpts, 1], [twoArgOpts, 2]].each do |argOpts, agNum|
			argOpts.each do |e|
				Opt.createOpt(e, agNum).each do |o|
					ret.insert o
				end
			end
		end
		if redirector
			Opt.createOpt(redirector[0], -1, redirector[1..-1]).each do |o|
				ret.insert o
			end
		end
		ret
	end
	def initialize (*args)
		require 'Yk/generator__'
		if !args[0].is_a? Object::Generator_
			noArgOpts, oneArgOpts, twoArgOpts, redirector, argv = args
		else
			g = args.shift
			yield self
			noArgOpts, oneArgOpts, twoArgOpts, redirector = args
		end
		noArgOpts = !noArgOpts.is_a?(Array) ? [noArgOpts] : noArgOpts
		oneArgOpts = !oneArgOpts.is_a?(Array) ? [oneArgOpts] : oneArgOpts
		twoArgOpts = !twoArgOpts.is_a?(Array) ? [twoArgOpts] : twoArgOpts
		@optList = getOptList(noArgOpts, oneArgOpts, twoArgOpts, redirector)
		@opt = Hash.new
		@args = []
		if !g
			if !argv
				g = ARGV.generator__ do
					return
				end
			else
				g = argv.generator__ do
					return
				end
			end
		end
		while true
			if +g != "-" && +g =~ /^\-/
				if +g =~ /^\--/ && +g =~ /\=/
					if s = @optList[$`]
						if s.argNum == 1 || s.argNum == -1
							(@opt[s.toShort] ||= []).push $'
						else
							raise Error.new("cannot use '=' for option '#{s}': number of arguments are not compatible (must be 1)")
						end
					else

					end
				elsif s = @optList[+g]
					if s.isRedirector?
						g.inc
						self.class.new(g, *s.redirectOpts) do |cmd|
							@opt[s.toShort] = cmd
						end
					elsif s.argNum >= 1 && s.isShort?
						s.argNum.times do
							g.inc
							(@opt[s.toShort] ||= []).push +g
						end
					elsif s.argNum == -1
						(@opt[s.toShort] ||= []).push nil
					elsif s.argNum == 0
						@opt[s.toShort] ||= 0
						@opt[s.toShort] += 1
					else
						raise Error.new("option `#{+g}' must have argment with equal or use short option.")
					end
				elsif (+g)[1] != ?- && (+g).size >= 3
					rpos = (+g).size - 1
					(+g)[1..-1].split("").each do |e|
						rpos -= 1
						tmp = "-" + e
						if !(s = @optList[tmp])
							raise Error.new("option `#{tmp}' is not specified.")
						elsif s.argNum != 0 && rpos != 0
							raise Error.new("option `#{tmp}' must have argment.")
						end
						if s.argNum >= 1
							s.argNum.times do
								g.inc
								(@opt[s.toShort] ||= []).push +g
							end
						else
							@opt[s.toShort] ||= 0
							@opt[s.toShort] += 1
						end
					end
				else
					raise Error.new("option `#{+g}' is not specified.")
				end
				g.inc
				next
			end
			@args.push +g
			g.inc
		end
	end
	def [] (arg)
		if arg.is_a? Integer
			@args[arg]
		else
			if @opt[arg] == nil
				if !(tmp = @optList[arg])
					nil
				elsif tmp.argNum >= 1
					[]
				else
					0
				end
			else
				@opt[arg]
			end
		end
	end
	def []= (arg, v)
		if arg.is_a? Integer
			@args[arg] = v
		else
			@opt[arg] = v
		end
	end
	def shift
		@args.shift
	end
	def pop
		@args.pop
	end
	def push (*args)
		@args.push *args
	end
	def unshift (*args)
		@args.unshift *args
	end
	def size
		@args.size
	end
	def each
		@args.each do |e|
			yield e
		end
	end
	def slice (*args)
		@args.slice(*args)
	end
	def slice! (*args)
		@args.slice!(*args)
	end
	def deleteOpt (arg)
		@opt.delete arg
	end
	def all_options
		arr = []
		@opt.each do |k, v|
			if k.size > 2
				head = "-" + k
				eqlMode = true
			else
				head = k
				eqlMode = false
			end
			if v.is_a? Integer
				v.times do
					arr.push head
				end
			else
				v.each do |e|
					if eqlMode
						arr.push head + "=" + e
					else
						arr.push head
						arr.push e
					end
				end
			end
		end
		arr
	end
	def to_a
		arr = all_options
		arr += @args
		arr
	end
	def join (arg)
		@args.join(arg)
	end
	def args
		@args.clone
	end
	def self.[] (arg)
		begin
			new(arg)
		rescue Error => e
			STDERR.write e.to_s.ln
			exit 1
		end
	end
end


def nil.optarg (opt)
	self
end


def nil.& (opt)
	self
end


class String
	def optarg (arg)
		if arg != nil && (tmp = self.strip)  != "" && (tmp2 = arg.to_s.strip) != ""
			tmp + " " + tmp2
		else
			""
		end
	end
	def & (arg)
		optarg(arg)
	end
	def ln
		self.chomp + "\n"
	end
	def ln!
		replace(chomp + "\n")
	end
end


def requireSib (*args)
	args.each do |e|
		if e !~ /^\//
			e = File.dirname(e) + "/" + File.basename(e, ".rb") + ".rb"
			if File.readable?(tmp = File.dirname($0) + "/" + e)
				require tmp
			end
		else
			require e
		end
	end
end


class String
	def underscore_escape
		UnderscoreEscaper.escape(self)
	end
	def underscore_unescape
		UnderscoreEscaper.unescape(self)
	end
end


def nil.underscore_escape
	"_Z_"
end


require 'Yk/__defun__'


class String
	def split_chunk (expr)
		s = self
		items = []
		while s && s =~ expr
			if $` && $` != ""
				items.push $`
			end
			items.push $&
			s = $'
		end
		if s && s != ""
			items.push s
		end
		items
	end
	def strip_comment! arg = nil
		arg == "" && arg = "#"
		if arg.is_a? String
			arg.__defun__ :__pre, self[/^\s*/]
			arg.__defun__ :__post, self[/\s*(#{Regexp.escape arg}[^\n]*|)(\n|$)/]
		elsif arg
			raise ArgumentError.new("argument should be a String")
		end
		gsub! /#{arg ? Regexp.escape(arg) : "\\#"}[^\n]*(\n|$)/, '\1'
		strip!
	end
	def strip_comment arg = nil
		arg == "" && arg = "#"
		if arg.is_a? String
			arg.__defun__ :__pre, self[/^\s*/]
			arg.__defun__ :__post, self[/\s*(#{Regexp.escape arg}[^\n]*|)(\n|$)/]
		elsif arg
			raise ArgumentError.new("argument should be a String")
		end
		ln = gsub(/#{arg ? Regexp.escape(arg) : "\\#"}[^\n]*(\n|$)/, '\1')
		ln.strip
	end
	def recomment arg
		ret = self
		if arg.respond_to? :__pre
			ret = arg.__pre + ret if arg.__pre
		end
		if arg.respond_to? :__post
			ret = ret + arg.__post if arg.__post
		end
		ret
	end
end


class Array
	def chomp!
		each do |e|
			e.chomp!
		end
		self
	end
end





module Process
	SignalList = Hash.new
	Signal.list.each do |k, v|
		SignalList["SIG" + k] = k.to_sym
		SignalList[("SIG" + k).to_sym] = k.to_sym
		SignalList[k.to_sym] = k.to_sym
		SignalList[k] = k.to_sym
		SignalList[v] = k.to_sym
	end
	def self.normalizeSignal (arg)
		if (tmp = SignalList[arg]) == nil
			raise ArgumentError.new("signal '#{arg}' is not defined")
		end
		tmp
	end
	DOTRAP_BLOCKS = Hash.new
	class ProcWithLocal < Proc
		def initialize (*args, &bl)
			super &bl
			@args = args
		end
		def call (*args)
			super *(@args + args)
		end
	end
	class TrapArr < Array
		def exit?
			@exit
		end
		def default?
			@default
		end
		attr_writer :exit, :default
	end
	DOTRAP_LIST = Hash.new do |h, k|
		h[k] = TrapArr.new
	end
	Signal.list.keys.each do |sig|
		DOTRAP_BLOCKS[sig.to_sym] = Proc.new do |lb|
			lb = normalizeSignal(lb)
			Signal.trap lb do end
			begin
				DOTRAP_LIST[lb].each do |e|
					if e.is_a? Proc
						e.call lb
					elsif e.is_a? String
						eval(e)
					else
						e.to_proc.call lb
					end
				end
				if DOTRAP_LIST[lb].default?
					Signal.trap lb, "DEFAULT"
					Process.kill lb, $$
				end
				if DOTRAP_LIST[lb].exit?
					exit
				end
			ensure
				Signal.trap lb, DOTRAP_BLOCKS[lb]
			end
		end
	end
	def self.addTrap (*args, &bl)
		inserter = Proc.new do |s, b|
			if ![nil, "SIG_IGN", "IGNORE", "", "SIG_DFL"].include? b
				if b == "EXIT"
					DOTRAP_LIST[s].exit = true
				elsif b == "DEFAULT"
					DOTRAP_LIST[s].default = true
				else
					DOTRAP_LIST[s].push bl
				end
			end
		end
		!bl and bl = args.pop
		args.size == 0 and args = Process::DOTRAP_BLOCKS.keys.map{|e| e.to_sym}.select{|e| e != :VTALRM}
		args.each do |e|
			e = e.to_sym
			if !DOTRAP_BLOCKS[e]
				raise ArgumentError.new("unknown signal name #{e}")
			end
			if !CYGWIN || e != :EXIT
				prev = Signal.trap(e, "SIG_IGN")
			end
			if prev != DOTRAP_BLOCKS[e]
				inserter.call e, prev
			end
			inserter.call e, bl
			Signal.trap(e, &DOTRAP_BLOCKS[e])
		end
	end
	def self.removeTrap (*args)
		toRemove = args.pop
		args.size == 0 and args = DOTRAP_BLOCKS.keys
		args.each do |e|
			if !DOTRAP_BLOCKS[e]
				raise ArgumentError.new("unknown signal name #{e}")
			end
			if toRemove == "EXIT"
				DOTRAP_LIST[e.to_sym].exit = false
			elsif toRemove == "DEFAULT"
				DOTRAP_LIST[e.to_sym].exit = false
			end
			DOTRAP_LIST[e.to_sym].delete toRemove
		end
	end
	@@set_kill_with_children = false
	def self.set_kill_with_children (*args)
		if !@@set_kill_with_children
			@@set_kill_with_children = true
			setpgrp rescue nil
			addTrap *args do |e|
				if (tmp = SignalList[e]) != :EXIT
					begin
						trap e, "IGNORE"
						begin
							Process.kill e, 0
						rescue
						end
					ensure
						trap e, &DOTRAP_BLOCKS[tmp]
					end
				end
			end
			at_exit do
				begin
					trap :TERM, "IGNORE"
					begin
						Process.kill :TERM, 0
					rescue
					end
				ensure
					trap :TERM, &DOTRAP_BLOCKS[:TERM]
				end
			end
		end
	end
end


class String
	def getDefinition (id)
		if id.is_a? Array
			seed = id.map{ |e| Regexp.escape(e) }.join("|")
			if self =~ /^\s*(#{seed})\s*\=\s*([^\s]+)/
				yield $1, $2
			end
		else
			if self =~ /^\s*#{Regexp.escape id}\s*\=\s*([^\s]+)/
				ret = $1
				ret.sub! /\#.*/, ""
				ret
			else
				if strip_comment == ""
					nil
				elsif (tmp = strip_comment.split).size == 1
					yield tmp[0], ""
				end
			end
		end
	end
end


class String
	def system (*args, **opts)
		if args.significant?
			Kernel.system *([self] + args), **opts
		else
			Kernel.system self
		end
	end
	def exec (*args, **opts)
		if args.significant?
			Kernel.exec *([self] + args), **opts
		else
			Kernel.exec self
		end
	end
end

module Etc
	class User
		def self.root? arg
			[:root, 0, "root"].include? arg
		end
		%W{name uid shell dir}.each do |m|
			eval <<~END
				def self.#{m} arg
					require 'etc'
					case arg
					when Integer
						Etc.getpwuid(arg)&.#{m}
					when String, Symbol
						Etc.getpwnam(arg.to_s)&.#{m}
					when nil
						Etc.getpwuid(Process.euid)&.#{m}
					else
						raise ArgumentError("\#{arg} is niether Integer not String")
					end
				end
			END
		end
		def self.home arg
			dir arg
		end
		def self.id arg
			uid arg
		end
		def initialize ent
			@ent = ent
		end
		%W{name passwd uid gid gecos dir shell change quota age class comment expire}.each do |e|
			eval %{
				def #{e}
					@ent.#{e}
				end
			}
		end
		def home
			dir
		end
		def password
			passwd
		end
		def self.each &bl
			begin
				if bl
					loop do
						yield new(Etc.getpwent || break)
					end
					nil
				else
					ret = []
					loop do
						ret.push(Etc.getpwent || break)
					end
					ret
				end
			ensure
				Etc.endpwent
			end
		end
	end

	[	%W{EUser euid},
		%W{RUser uid}
	].each do |cls, id|
		eval <<~ALLED
			class #{cls} # effective user
				def self.root?
					Process.#{id} == 0
				end
				def self.current? arg
					if arg
						Process.#{id} == User.uid(arg)
					else
						true
					end
				end
				%W{name uid shell dir}.each do |m|
					eval <<~END
						def self.\#{m} arg = nil
							if !arg || User.id(Process.#{id}) == User.id(arg)
								User.\#{m}(Process.#{id})
							end
						end
					END
				end
				def self.home arg = nil
					dir arg
				end
				def self.id arg = nil
					uid arg
				end
			end
		ALLED
	end


	class LUser # login user
		def self.getLoginUserId
			User.id(ENV['SUDU_USER'] || ENV['USER'] || RUser.name)
		end
		def self.root?
			User.root? getLoginUserId
		end
		%W{name uid shell dir}.each do |m|
			eval <<~END
				def self.#{m} arg = nil
					if !arg || (lid = getLoginUserId) == User.id(arg)
						User.#{m}(lid || getLoginUserId)
					end
				end
			END
		end
		def self.home arg = nil
			dir arg
		end
		def self.id arg = nil
			uid arg
		end
	end
end

class Array
	protected
	def __command_tz__2 mode, env, opts, euid = nil, ruid = nil
		prc = Proc.new do
			Process.euid = euid if euid
			Process.uid = ruid if ruid
			if env
				Kernel.exec env, *self, **opts
			elsif opts[:env]
				o = opts.clone
				o.delete(:env)
				Kernel.exec opts[:env], *self, **o
			else
				Kernel.exec *self, **opts
			end
		end
		case mode
		when :system
			pid = fork do
				prc.call
			end
			Process.waitpid pid
			case $?.exitstatus
			when 0
				return true
			when Integer
				return false
			else
				return nil
			end
		when :exec
			prc.call
		end
	end
	def __command_tz__ mode, a, b, opts
		if a.is_a? Hash
			env, uname = a, b
		elsif b.is_a? Hash
			env, uname = b, a
		elsif !a.nil?
			uname, env = a, b
		elsif !b.nil?
			uname, env = b, a
		end
		if opts[:user]
			o = opts.clone
			uname = o.delete(:user)
			opts = o
		end
		if opts[:ruser]
			o = opts.clone
			runame = o.delete(:ruser)
			opts = o
		end
		if opts[:euser]
			o = opts.clone
			euname = o.delete(:euser)
			opts = o
		end
		if Etc::EUser.current? uname
			__command_tz__2 mode, env, opts
		elsif Etc::User.root? uname
			require "shellwords"
			if (File.executable?(tmp = "/usr/sbin/cansudo") && system(tmp) && $? == 0 && STDIN.tty?) or "/etc/group".read =~ /\nwheel|sudo:.*\b(#{Regexp.escape Etc.getpwuid(Process.euid).name})\b/
				["sudo", *self].__command_tz__2 mode, env, opts
			else
				["su",  "-c",  Shellwords.join(self)].__command_tz__2 mode, env, opts
			end
		else
			if Process.euid == 0
				__command_tz__2 mode, env, opts, Etc::User.id(euname||uname), Etc::User.id(runame||uname)
			else
				["su", Etc::User.name(uname),  "-c",  Shellwords.join(self)].__command_tz__2 mode, env, opts
			end
		end
	end
	public
	def system a = nil, b = nil, **opts
		__command_tz__ :system, a, b, opts
	end
	def exec a = nil, b = nil, **opts
		__command_tz__ :exec, a, b, opts
	end
	def popen (mode = "r")
		require 'Yk/shellquote'
		IO.popen condSQuote, mode do |e|
			yield e
		end
	end
end


class Object
	def __context_var__ (label, value)
		require 'Yk/__defun__'
		ar = (@__context_var_arr__ ||= Hash.new{|h, k| h[k] = Hash.new{|h2, k2| h2[k2] = []}})[label][Thread.current]
		if !respond_to? label
			__defun__ label do
				@__context_var_arr__[label][Thread.current][-1]
			end
		end
		ar.push value
		ret = yield
		ar.pop
		ret
	end
end


def Process.set_detach (pid, &bl)
	@@datachList ||= Hash.new { |h, k|
		h[k] = []
		Thread.new do
			t = Process.detach(k)
			list = h[k]
			t.join
			h[k] = nil
			list.each do |e|
				e.call
			end
		end
	}
	if @@datachList[pid] != nil
		@@datachList[pid].push bl
	end
end


class Object
    def instanceVariableSet (k, v)
        first = true
        key = "@"
        k.split("_").each do |e|
            if first
                e.downcase!
                first = false
            else
                e.capitalize!
            end
            key += e
        end
        instance_variable_set(key, v)
    end
end



class String
	def lspaces
		self =~ /^\s*/
		$&
	end
	def rspaces
		self =~ /\s*$/
		$&
	end
	def rspaces_comment
		self =~ /\s*\#.*$|\s*$/
		$&
	end
	def example
		self
	end
	def escapeHTML
		require 'cgi'
		CGI.escapeHTML self
	end
	def escapeURL
		require 'cgi'
		CGI.escape self
	end
end


class Array
	def first_result &bl
		each do |e|
			res = bl.call e
			return res if res
		end
		nil
	end
end


class String
	def basename_of arg
		if self[- arg.size .. -1] == arg
			self[0 .. self.size - arg.size - 1]
		else
			nil
		end
	end
end



def nil.example
	""
end

class Regexp
	def example
		s = to_s.gsub /\\s/, " "
		s.gsub! /\?\-\w+:/, ""
		s.gsub! /\\d/, "0"
		s.gsub! /\\n/, "\n"
		s.gsub! /\\r/, "\r"
		s.gsub! /\\(.)/, '\1'
		s.gsub! /\(/, ""
		s.gsub! /\)/, ""
		s.gsub! "$", ""
		s.gsub! "^", ""
		s.gsub! /.\*/, ""
		s.gsub! /(.)\+/, '\1'
		s
	end
end

def waitUntil t, step = 1
	cnt = t
	while !yield t - cnt
		if cnt == 0
			return false
		end
		sleep step
		cnt -= 1
	end
	return true
end

require 'set'

def genpasswd sz = 12, str = "abcdefghijkmnpqrstuvwxyABCDERFHJKMNPQRSTUVWXY3456789!#$%&`()=~{}*+@_?/><"
	r = ""
	sz.times do
		r += str[rand(str.size)]
	end
	r
end
def genpassword *args
	genpasswd
end


module ProcWithArguments
	refine Symbol do
		def [] *bin_args
			proc do |*args|
				obj = args.shift
				obj.method(self).curry[*bin_args, *args]
			end
		end
	end
end
	

# "/etc/asdf".¿[:_e?]&.

