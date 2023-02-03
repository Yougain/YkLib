#!/usr/bin/env ruby


require 'continuation'


class Fetch
	def self.caller_binding
	  cc = nil     # must be present to work within lambda
	  count = 0    # counter of returns

	  set_trace_func lambda { |event, file, lineno, id, binding, klass|
	    # First return gets to the caller of this method
	    # (which already know its own binding).
	    # Second return gets to the caller of the caller.
	    # That's we want!
	    if count == 2
	      set_trace_func nil
	      # Will return the binding to the callcc below.
	      cc.call binding
	    elsif event == "return"
	      count += 1
	    end
	  }
	  # First time it'll set the cc and return nil to the caller.
	  # So it's important to the caller to return again
	  # if it gets nil, then we get the second return.
	  # Second time it'll return the binding.
	  return callcc { |cont| cc = cont ; nil}
	end
	#module_function :caller_binding

	BlockStrList = Hash.new
	ANON = Object.new
	attr :direct_mode, true
	def initialize obj
		@obj = obj
	end
	class BlockInfo
		class Select < Array
			def initialize *args
				args.each do |e|
					push e
				end
			end
		end
		attr :params, true
		def self.each_match item, pat
			if pat == ANON
				true
			elsif pat.is_a? Select
				pat.each do |e|
					if each_match(item, e)
						return true
					end
				end
				return false
			elsif !item.is_a?(Array) || !pat.is_a?(Array)
				item == pat
			else # both is array
				if pat.size <= item.size
					pat.each_with_index do |e, i|
						if !each_match(item[i], e)
							return false
						end
					end
					#pp ["item", item]
					#pp ["pat", pat]
					true
				else
					false
				end
			end
		end
		def self.rec_find_match sexe, pat
			return sexe if each_match sexe, pat
			case sexe.size
			when 0
				pat == []
			when 1
				item = sexe[0]
				if each_match item, pat
					item
				elsif item.is_a?(Array) || (item.respond_to?(:to_ary) && (item = item.to_ary))
					rec_find_match item, pat
				end
			else
				m = sexe.size.div(2)
				rec_find_match(sexe[0 ... m], pat) or rec_find_match(sexe[m .. -1], pat)
			end
		end
		def self.rec_find_match_all sexe, pat, ret = []
			case sexe.size
			when 0
				ret
			when 1
				item = sexe[0]
				if each_match item, pat
					ret.push item
				elsif item.is_a?(Array) || (item.respond_to(:to_ary) && (item = item.to_ary))
					rec_find_match_all item, pat, ret
				end
			else
				m = sexe.size.div(2)
				rec_find_match_all(sexe[0 ... m], pat, ret)
				rec_find_match_all(sexe[m .. -1], pat, ret)
			end
			ret
		end
		 	def self.dosexp path
		 		require 'ripper'
		 		sexpBuilder2 = Ripper.new(path, "-", 1)
				(class << sexpBuilder2; self; end).module_eval do   #:nodoc:
				    private

				    ::Ripper::PARSER_EVENT_TABLE.each do |event, arity|
				      if /_new\z/ =~ event.to_s and arity == 0
				        module_eval(<<-End, __FILE__, __LINE__ + 1)
				          def on_#{event}
				            []
				          end
				        End
				      elsif /_add\z/ =~ event.to_s
				        module_eval(<<-End, __FILE__, __LINE__ + 1)
				          def on_#{event}(list, item)
				            list.push item
				            list
				          end
				        End
				      else
				        module_eval(<<-End, __FILE__, __LINE__ + 1)
				          def on_#{event}(*args)
				            [[:#{event}, [lineno(), column()]], *args]
				          end
				        End
				      end
				    end

				    ::Ripper::SCANNER_EVENTS.each do |event|
				      module_eval(<<-End, __FILE__, __LINE__ + 1)
				        def on_#{event}(tok)
				          [:@#{event}, tok, [lineno(), column()]]
				        end
				      End
				    end
				    self
				end
				sexpBuilder2.parse  	
			end

		List = Hash.new
		def self.getPosAfter all, lno, expr
			i = 0
			all.each_line do |ln|
				i += 1
				if lno == i && ln =~ expr
					return [i, $`.size + $&.size + 1]
				end
			end
			return nil
		end
		def self.getContent all, from, to
			if from[0] > to[0] || (from[0] == to[0] && from[1] > to[1])
				raise Exception.new "range error"
			end
			i = 0
			lns = ""
			all.each_line do |ln|
				i += 1
				if i == from[0]
					if from[0] != to[0]
						lns += ln[from[1] - 1 .. -1]
					else
						lns += ln[from[1] - 1 .. to[1] - 1]
						if lns[-1] == "d"
							lns = lns[0..-4]
						elsif lns[-1] == "}"
							lns = lns[0..-2]
						end
						if lns[0] == "|"
							lns = lns[1..-1]
						end
						return lns
					end
				elsif i == to[0]
					lns += ln[0 .. to[1] - 1]
					if lns[-1] == "d"
						lns = lns[0..-4]
					elsif lns[-1] == "}"
						lns = lns[0..-2]
					end
					if lns[0] == "|"
						lns = lns[1..-1]
					end
					return lns
				elsif from[0] < i && i < to[0]
					lns += ln
				end
			end
			raise Exception.new "range error"
		end
		attr :blockBody
		def initialize params, path, lno, bstr
			@params = params
			@path = path
			@lineNo = lno
			if bstr
				@blockBody = %{
					Proc.new do |#{["_f", *params].join(", ")}|
						#{bstr}
					end
				}
			end
			List[path + ":#{lno}"] = self
		end
		FILE_CONTENT = Hash.new
		FILE_SEXP = Hash.new
		OldCleared = Hash.new
		def self.clearOld ph, t, forceTrue = true
			found = false
			if File.directory? ph
				Dir.open ph do |d|
					d.each do |f|
						if f != "." && f != ".."
							f = ph + "/" + f
							if File.directory?(f)
								if !clearOld f, t, false
									require "fileutils"
									FileUtils.rmdir f
								end
							elsif File.mtime(f) < t
								File.unlink f
							else
								found = true
							end
						end
					end
				end
			end
			return forceTrue ? true: found
		end
		def self.createFromFiles path, lno, pth, ph
			params = nil
			blockContent = nil
			w = pth + "/" + ".params"
			t = File.mtime(path)
			if File.exist?(w) && File.mtime(w) > t
				File.open w do |f|
					f.flock File::LOCK_SH
					params = f.read.split /\s+/
				end
			end
			w = pth + "/" + ".blockContent"
			if File.exist?(w) && File.mtime(w) > t
				File.open w do |f|
					f.flock File::LOCK_SH
					blockContent = f.read
				end
			end 
			if !params
				OldCleared[path] ||= clearOld(ph, t) 
				return nil
			end
			self.new params, path, lno, blockContent
		end
		def self.getBlockInfo path, lno, key, label, blKey
			label = label.to_s
			pth = (ph = File.expand_path("~/.tmp") + "/Yk/site_ruby/fetch.rb/" +  path) + "/" + lno.to_s + "/" +  key + "/" + label
			item = List[path + ":#{lno}"] || createFromFiles(path, lno, pth, ph)
			if item
				return item
			end
			all = FILE_CONTENT[path] ||= IO.read(path)
			sexp = FILE_SEXP[path] ||= dosexp(all)
			lst = rec_find_match sexp, 
				[[:method_add_block],
					[[:call],
						[[:call],
							ANON,
		     				:".",
		 					[:@ident, key]
						],
						:".",
						[:@ident, label, [lno]]
					],
					[[Select.new(:do_block, :brace_block)]]
				]
			if lst
				pLst = rec_find_match lst,
					[	[:method_add_block],
						[[:call],
							[[:call],
								ANON,
			     				:".",
			 					[:@ident, key]
							],
							:".",
							[:@ident, label, [lno]]
						],
						[[Select.new(:do_block, :brace_block)],
							[[:block_var], [[:params]]]
						]
					]
				params = []
				if pLst
					if pLst[2][1][1][1]
						pLst[2][1][1][1].each do |e|
							params.push e[1]
						end
					end
					pLst[2][1][1].each do |e|
						if e.is_a?(Array) && e[0].is_a?(Array) && e[0][0] == :rest_param
							params.push "*" + e[1][1]
						end
					end
				end
				require "pathname"
				Pathname.new(pth).mkpath
				File.open pth + "/.params", "w" do |fw|
					fw.flock File::LOCK_EX
					fw.write params.join(" ")
				end
				if params[0] =~ /^_f/
					self.new params, path, lno, nil
				else
					c = pLst && getContent(all, pLst[2][1][0][1], pLst[2][0][1])
					c ||= getContent(all, getPosAfter(all, lno, /\b#{key}\s*\.\s*#{label}\b.*(\bdo\b|\{)/), lst[2][0][1])
					File.open pth + "/.blockContent", "w" do |fw|
						fw.flock File::LOCK_EX
						fw.write c
					end
					self.new params, path, lno, c
				end
			else
				nil
			end
			
		end
	end
	def method_missing label, *fargs, &bl
		@label = label
		super if !@obj.respond_to? @label
		loc = caller_locations(1)[0]
		if @blockInfo = BlockInfo.getBlockInfo(loc.path, loc.lineno, "__fetch__", @label, "fetch")
			bd = @blockInfo.blockBody
			if bd
				return unless bnd = Fetch.caller_binding
				@block = bnd.eval(bd)
			end
		end
		@block ||= bl
		entity *fargs
	end
	def normArray a
		if a.size == 1
			if a[0].is_a?(Array)
				return a[0]
			elsif a[0].respond_to? :to_ary
				return a.to_ary
			end
		end
		return a
	end
	def entity *fargs
		if callcc{|cc| @start = cc; true}
			@iter_rval = iterate *fargs
			@setup_iter_rval.call false
		else
			@start = nil
			@bl_rval = nil
			loop do
				count = 0
				a = @args
				if @blockInfo.params.size > (@blockInfo.blockBody ? 1 : 2)
					a = normArray(a)
				end
				#p [__LINE__, @args, a]
				set_trace_func lambda { |event, file, lineno, id, binding, klass|
				 	if event == "line"
				 		count += 1
				 		if count == 2
				 			@blBind = binding
				 			set_trace_func nil
				 		end
				 	end
				}
				@bl_rval = @block.call self, *a
				if !callcc{|cc| @setup_iter_rval = cc; true}
					break @iter_rval
				end
				if callcc{|cc| @block_cont = cc; true}
					@iterate_cont.call false;
				end
			end
		end
	end
	def iterate *fargs
		@obj.__send__(@label, *fargs, &self)
	end
	def evaluate
		if @blockInfo.params.size > (@blockInfo.blockBody ? 1 : 2)
			@args = normArray(@args)
		end
		@blockInfo.params.each_with_index do |vl, im|
			i = @blockInfo.blockBody ? im : im - 1
			if i == -1
				@blBind.eval("#{vl} = ObjectSpace._id2ref(#{self.__id__})");
			else
				if @args.size <= i
					if vl[0..0] == "*"
						@blBind.eval("#{vl} = []")
					else
						@blBind.eval("#{vl} = nil")
					end
				else
					if vl[0..0] == "*"
						estr = "#{vl[1..-1]} = ["
						i.upto @args.size - 1 do |j|
							if j != i
								estr += ","
							end
							estr += "ObjectSpace._id2ref(#{@args[j].__id__})"
						end
						estr += "]"
						@blBind.eval estr
					else
						@blBind.eval("#{vl} = ObjectSpace._id2ref(#{@args[i].__id__})");
					end
				end
			end
		end
	end
	def fetch fret = nil
		if callcc{|cc| @fetch = cc; true}
			@bl_rval = fret
			@iterate_cont.call false
		else
			@fetch = nil
			evaluate
		end
		true
	end
	def call *args
		@args = args
		if callcc{|cc| @iterate_cont = cc; true}
			if @start
				@start.call false
			elsif @fetch
				@fetch.call false
			else
				@block_cont.call false
			end
		else
			@bl_rval
		end
	end
	def to_proc
		Proc.new do |*args|
			call *args
		end
	end
	def self.find
		loc = caller_locations(2)[0]
		FetchRangeList.find loc
	end
end


def fetch *frets
	return unless bnd = Fetch.caller_binding
	f = bnd.eval("_f")
	if !f.is_a? Fetch
		raise Exception.new("JumpError")
	end
	case frets.size
	when 0
		fret = nil
	when 1
		fret = frets[0]
	else
		fret = frets
	end
	f.fetch fret
end


class Object
	def __fetch__ &bl
		f = Fetch.new self
		if bl
			f.direct_mode = true
			bl.call f
		else
			f
		end
	end
end


if File.expand_path($0) == __FILE__

	#	[1, 2, 3, 4, 5].__fetch__.each do |e|
	#		if e == 3
	#			print "[#{e}, #{(fetch and e)}], "
	#		else
	#			print "#{e}, "
	#		end
	#	end

	def test
		[1, 2, 3, 4, 5].__fetch__.each { |_f, e|
			if e == 3
				print "[#{e}, #{(fetch and e)}], "
			else
				print "#{e}, "
			end
		}
	end

	print "\n"
	test
	print "\n"
	test
	test


	i = 0
	[[1, 2, 3], 4, 5, [6, 7], [8, 9, 10, 11], 12, 13].__fetch__.each do |*j|
		if i == 3
			print "("
		end
		print "[#{j}]"
		if i == 3
			fetch
			print ", [#{j}])"
		end
		print "\n"
		i += 1
	end

	[[1, 2, 3], 4, 5, [6, 7], [8, 9, 10, 11], 12, 13].each do |*j|
		if i == 3
			print "["
		end
		print "[#{j}]"
		print "\n"
		i += 1
	end

end


print "\n"



