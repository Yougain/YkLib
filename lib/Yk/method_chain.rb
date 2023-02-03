#!/usr/bin/env ruby


require 'binding_of_caller'


class Module
	def get_instence_method label
		begin
			org_mth = instance_method(label) # original method
		rescue NameError
		end
		if org_mth && instance_methods(false).include?(label)
			return org_mth
		end
	end
end

def Modules *marr, &bl
	marr.each do |m|
		if m.is_a?(Symbol) || m.is_a?(String)
			m = binding.of_caller(1).eval(m.to_s)
		end
		case m
		when ::Class
			m.class_eval &bl
		when ::Module
			m.module_eval &bl
		else
			raise ArgumentError.new("'#{m.inspect}' is not a module")
		end
	end
end

class Class
	def include *modules
		MethodChain.doExtend self, *modules do
			super
		end
	end
end


class Object
	def extend *modules
		cls = class << self; self; end
		MethodChain.doExtend cls, *modules do
			super
		end
	end
	def __method_chain_caller__ l
		if caller[1] =~ /^(.+?):(\d+)(?::in `(.*)')?/
			f, lno, fname = $1, $2.to_i, $3
			callerMethod = MethodChain.getMethod($1, $2.to_i, l)
			mp = MethodChain::PrevList[callerMethod]
			if mp
				return mp
			else
				mdl =  MethodChain::ModList[callerMethod]
				if om = MethodChain::OrgList[[mdl, l]]
					return om
				else
					as = (class << self; self; end).ancestors
					(as.index(mdl) + 1 ... as.size).each do |i|
						c = as[i]
						if ent = MethodChain::EntryList[c][l]
							return ent
						elsif om = MethodChain::OrgList[[c, l]]
							return om
						elsif m = c.get_instence_method(l)
							if m.source_location[0] != "(MethodChain)"
								return m
							end
						end
					end
					raise ArgumentError.new("No super method defined for '#{l}'")
				end
			end
		else
			raise ArgumentError.new("Unknown error: cannot find '#{l}'")
		end
	end
end

class MethodChain
	def self.doExtend cls, *modules
		ks = Hash.new
		(modules + [cls]).each do |mdl|
			MethodChain::EntryList[mdl]&.keys&.each do |k|
				ks[k] = true
			end
		end
		yield
		ks.keys.each do |k|
			MethodChain.checkDispatcher k
			if !MethodChain::EntryList[cls][k]
				om = cls.get_instance_method(k)
				if !om || om.source_location[0] != "(MethodChain)"
					MethodChain::OrgList[[cls, k]] ||= om
					cls.class_eval %{
						def #{k} (...)
							cls = ::ObjectSpace._id2ref(#{cls.__id__})
							cls.ancestors.each do |a|							
								if ent = MethodChain::EntryList[a][:#{k}]
									return mth.bind(self).call(...)
								elsif om = MethodChain::OrgList[[cls, :#{k}]]
									return om.bind(self).call(...)
								elsif m = c.get_instence_method(l)
									if m.source_location[0] != "(MethodChain)"
										return m.bind(self).call(...)
									end
								end
							end
							raise ArgumentError.new("No method defined for '#{l}'")
						end
					}, "(MethodChain)", 1
				end
			end
		end
	end
	PrevList = Hash.new
	EntryList = Hash.new{|h, k| h[k] = {}}
	OrgList = {}
	ModList = {}
	def self.getMethod f, lno, label
		MethodRange.getMethod(f, lno, label)
	end
	def self.checkDispatcher l
		if !(Object.instance_method("__method_chain_caller_#{l}") rescue nil)
			Object.class_eval %{
				def __method_chain_caller_#{l} (...)
					mth = __method_chain_caller__ :#{l}
					mth.bind(self).call(...)
				end
			}
		end
	end
	def self.override &bl
		cm = binding.of_caller(1).eval("self")
		cm = ::Object if cm == TOPLEVEL_BINDING.eval("self")
		if !cm.is_a? ::Module
			raise Exception.new("called at non-module context")
		end
		new_defs = Module.new &bl
		new_defs.instance_methods(false).each do |l| # newly defined method
			checkDispatcher l
			new_mth = MethodRange.emerge(cm, new_defs.instance_method(l), "__method_chain_caller_#{l}") # new_mth redefined as __method_chain_caller_
			ModList[new_mth] = cm
			old_ent = EntryList[cm][l]
			EntryList[cm][l] = new_mth
			if !old_ent
				OrgList[[cm, l]] = cm.get_instence_method(l) # original method defined in this class
				if cm.is_a? ::Class
					cm.class_eval %{
						def #{l} (...)
							cls = ::ObjectSpace._id2ref(#{cm.__id__})
							cls.ancestors.each do |a|
								mth = MethodChain::EntryList[a][:#{l}]
								if mth
									return mth.bind(self).call(...)
								end
							end
						end
					}, "(MethodChain)", 1
				end
			else
				PrevList[new_mth] = old_ent
			end
		end
	end
	class MethodRange
		class DefnList
			DFNList = {}
			def self.getRangeByStart f, name, lno
				(DFNList[f] ||= new(f)).getRangeByStart name, lno
			end
			def initialize f
				storedF = ENV['HOME'] + "/.tmp/ruby/Yk/#{File.basename($0)}/" + File.expand_path(f) + "/defnList"
				if File.mtime(f) < (File.mtime(storedF) rescue Time.at(0))
					@defnList = Marshal.load(IO.binread(storedF))
					return
				end
				if f == "(eval)"
					raise ArgumentError.new("cannot use MethodChain for method in evaluated value")
				end
				root = RubyVM::AbstractSyntaxTree.parse_file(f)
				@defnList = Hash.new
				(regMethodDef = -> node do
					if node.inspect =~/\A#\<RubyVM::AbstractSyntaxTree::Node:DEFN@(\d+):\d+\-(\d+):\d+/
						rg = $1.to_i .. $2.to_i
						lst = (@defnList[node.children[0]] ||= [])
						pos = lst.bsearch_index do |item|
							item.first >= rg.first
						end
						pos ||= lst.size
						if pos
							lst.insert pos, rg
						else
							lst.push rg
						end
					end
					if defined?(node.children)
						node.children.each do |e|
							regMethodDef.(e)
						end
					end
				end).(root)
				require "fileutils"
				FileUtils.mkdir_p File.dirname(storedF)
				IO.binwrite(storedF, Marshal.dump(@defnList))
			end
			def getRangeByStart name, lno
				lst = @defnList[name]
				pos = lst.bsearch_index do |item|
					item.first >= lno
				end
				if pos && lst[pos]
					if [pos - 1, pos + 1].find{lst[_1]&.first == lno}
						raise ArgumentError.new("multiple definition of method '#{name}', found in one line")
					else
						lst[pos]
					end
				else
					nil
				end
			end
		end
		OList = {}
		FLnList = {}
		List = Hash.new{|h, k| h[k] = []}
		Item = Struct.new(:rg, :mth)
		attr_reader :method_chain_caller
		def self.emerge cls, mth, l
			(OList[[cls, mth]] ||= new cls, mth, l).method_chain_caller
		end
		def initialize cls, mth, l
			f, lno = mth.source_location
			if f == "(eval)"
				raise ArgumentError.new("cannot use MethodChain for method in evaluated value")
			end
			mrg = DefnList.getRangeByStart f, mth.name, lno
			if !mrg
				raise ArgumentError.new("cannot find 'def #{mth.name}': please note that currently alias_method and method defined in eval are not supported")
			end
			lns = (FLnList[f] ||= IO.readlines(f))
			if (toEv = lns[mrg.first - 1 .. mrg.last - 1].join).sub! /\A\s*def\s+(\w+)/, "def #{l}"
				(m = Module.new).module_eval toEv, f, mrg.first
				@method_chain_caller = m.instance_method(l)
			else
				raise ArgumentError.new("cannot find 'def #{mth.name}': please note that currently alias_method and method defined in eval are not supported")
			end
			pos = (l = List[[f, mth.name]]).bsearch_index{|e| e.rg.first >= mrg.first}
			if pos
				if l[pos].rg.first != mrg.first
					l.insert pos, Item.new(mrg, mth)
				else
					raise ArgumentError.new("method, '#{mth.name}' is defined twice in the same line")
				end
			else
				l.push Item.new(mrg, @method_chain_caller)
			end
		end
		def self.getMethod f, lno, label
			lst = List[[f, label]]
			pos = lst.bsearch_index{|e| lno <= e.rg.first}
			if pos == nil
				pos = lst.size
			end
			smallestIdx = nil
			smallestRangeSize = nil
			if pos
				hit = -> i do
					item = lst[i]
					if item
						if item.rg.first < lno && lno < item.rg.last
							if !smallestRangeSize&.<=(item.rg.size)
								smallestRangeSize = item.rg.size
								smallestIdx = i
							end
							break item.mth
						elsif item.rg.first == lno || lno == item.rg.last
							raise ArgumentEror.new("ambigous calling origin: 'super' should not be located in the same line with method definition starting by 'def' nor finising by 'end'")
						end
					end
					nil
				end
				i = pos - 1
				while hit.(i)
					i -= 1
				end
				i = pos
				while hit.(i)
					i += 1
				end
				if !smallestIdx
					raise ArgumentError.new("cannot find caller")
				end
				return lst[smallestIdx].mth
			end
			raise ArgumentError.new("cannot find calling origin, 'super'")
		end
	end
end


if File.expand_path($0) == File.expand_path(__FILE__)

	class Ans
		def test1
			p ":Ans::org_test1"
		end
	end




	class Des < Ans
		def test1
			p ":Des::org_test1"
			super
		end
	end

	Des.new.test1


	class Des
		MethodChain.override do
			def test1
				p ":Des::new_test1"
				super
			end
		end
	end

	(d = Des.new).test1

	class << d
		MethodChain.override do
			def test1
				p ":Singleton::new_test1"
				super
			end
		end
	end


	class << d
		MethodChain.override do
			def test1
				p ":Singleton::new_new_test1"
				super
			end
		end
	end

	d.test1

end
