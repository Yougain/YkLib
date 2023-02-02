#!/usr/bin/env ruby


require 'continuation'


def caller_binding
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


class Ripper
	def sexp2
	end
end


class Fetch
	BlockStrList = Hash.new
	ANON = Object.new
	attr :string_mode, true
	def initialize obj
		@obj = obj
	end
	def eval_block_str s, b
		if s =~ /\|\s*([_\w][_\w\d]*)\s*(\,\s*([_\w][_\w\d]*)\s*)*\|/
			i = 0
			argNames = []
			loop do
				argNames.push($~[i * 2 + 1] || break)
				i += 1
			end
			blkStr = $'
			argLabels = argNames.map{|e| ":" + e}
			blkStr = %{
				Proc.new do |__fobj, #{argNames.join(', ')}|
					__fobj.init_block_args binding, #{argLabels.join(', ')}
					#{blkStr.gsub!(/\bfetch\b/, "__fobj.fetch")}
				end
			}
			b.eval blkStr
		end
	end
	def each_match item, pat
		if pat == ANON
			true
		elsif !item.is_a?(Array) || !pat.is_a?(Array)
			item == pat
		else # both is array
			if pat.size <= item.size
				pat.each_with_index do |e, i|
					if !each_match(item[i], e)
						return false
					end
				end
				true
			else
				false
			end
		end
	end
	def rec_find_match sexe, pat
		case sexe.size
		when 0
			nil
		when 1
			item = sexe[0]
			if each_match item, pat
				item
			else if item.is_a?(Array) || (item.respond_to(:to_ary) && (item = item.to_ary))
				rec_find_match item, pat
			end
		else
			m = sexe.size.div(2)
			rec_find_match(sexe[0 ... m], pat) or rec_find_match(sexe[m .. -1], pat)
		end
	end
	def rec_find_match_all sexe, pat, ret = []
		case sexe.size
		when 0
			ret
		when 1
			item = sexe[0]
			if each_match item, pat
				ret.push item
			else if item.is_a?(Array) || (item.respond_to(:to_ary) && (item = item.to_ary))
				rec_find_match_all item, pat, ret
			end
		else
			m = sexe.size.div(2)
			rec_find_match_all(sexe[0 ... m], pat, ret)
			rec_find_match_all(sexe[m .. -1], pat, ret)
		end
		ret
	end
	def getBlockContent
	def replaceEach
	def modifyBlock str, key, label, lno, blKey, chead
		sexp = Ripper.sexp2 str
		lst = rec_find_match sexp, 
			[:method_add_block,
				[:call,
					[:call,
						ANON,
	     				:".",
	 					[:@ident, key]
					],
					:".",
					[:@ident, label, [lno]]
				],
				[:do_block]
			]
		if lst
			pLst = rec_find_match lst,
				[:method_add_block,
					[:call,
						[:call,
							ANON,
		     				:".",
		 					[:@ident, key]
						],
						:".",
						[:@ident, label, [lno]]
					],
					[:do_block,
						[:block_var, [:params]]
					]
				]
			if pLst
				pLst[2][1][1][1].each do |e|
					params.push e[1]
				end
				pLst[2][1][1].each do |e|
					if e[0] == :rest_param
						params.push "*" + e[1][1]
					end
				end
			end
			blKey_pos_list = rec_find_match_all lst[2][2], [:@ident, blKey]
			bStr, lno, cno = getBlockContent lst
			blKey_pos_list.each do |e|
				id, bk, pos = e
				replaceEach bStr, [lno, cno], pos, chead + "." + blKey
			end
			paramLabels = params.map{|e| ":" + e}
			paramLabels.unshift "binding"
			params.unshift chead
			bStr = %{
				Proc.new do |#{params.join(', ')}|
					#{chead}.init_block_args #{argLabels.join(', ')}
					#{bStr}
				end
			}
		else
			nil
		end
	end
	def method_missing label, *fargs, &bl
		return unless bnd = caller_binding
		@label = label
		super if !@obj.respond_to? @label
		if @string_mode
			loc = caller_locations(1)[0]
			lpos = loc.path + ":#{loc.lineno}"
			bstr = BlockStrList[lpos] ||= modifyBlock(loc.path.read, "__fetch__", @label, loc.lineno, "fetch", "__fobj")
			@block = bnd.eval bstr
		else
			@block = bl
		end
		entity *fargs
	end
	def entity *fargs
		if callcc{|cc| @start = cc; true}
			@block.call self, nil
			@iterate_cont.call false
		else
			iterate *fargs
		end
	end
	def iterate *fargs
		@obj.method(@label).call *fargs, &self
	end
	def evaluate
		@vlabels.each_with_index do |vl, i|
			@scope.eval("#{vl} = ObjectSpace._id2ref(#{@args[i].__id__})");
		end
	end
	def init_block_args s, *vlabels
		@scope = s
		@vlabels = vlabels
		if !callcc{|cc| @init_args = cc; true}
			evaluate
		end
		if @fetch
			@fetch.call false
		end
		if !@iterate_cont
			@start.call false
		end
	end
	def fetch
		if callcc{|cc| @fetch = cc; true}
			@iterate_cont.call false
		else
			@fetch = nil
		end
		true
	end
	def call *args
		@args = args
		if callcc{|cc| @iterate_cont = cc; true}
			if @init_args
				@init_args.call false
			end
		end
	end
	def to_proc
		Proc.new do |*args|
			call *args
		end
	end
end


class Object
	def __fetch__ &bl
		f = Fetch.new self
		if bl
			bl.call f
		else
			f.string_mode = true
			f
		end
	end
end


if File.expand_path($0) == __FILE__
	[1, 2, 3, 4, 5].__fetch__ do |fobj|
		fobj.each do |e|
			fobj.init_block_args binding, :e
			if e == 3
				print "[#{e}, #{(fobj.fetch and e)}], "
			else
				print "#{e}, "
			end
		end
	end
	[1, 2, 3, 4, 5].__fetch__.each %q{ |e|
		if e == 3
			print "[#{e}, #{(fetch and e)}], "
		else
			print "#{e}, "
		end
	}
	exit 1
	[1, 2, 3, 4, 5].__fetch__.each do |e|
		if e == 3
			print "[#{e}, #{(fetch and e)}], "
		else
			print "#{e}, "
		end
	end
end


print "\n"



