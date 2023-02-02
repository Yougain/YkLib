
class Module
	def override_prev (*mnames)
		mnames.each do |mname|
			alias_method "__org_" + mname.to_s, mname
			if !defined? @prev_overriden
				@prev_overriden = Hash.new
			end
			if @prev_overriden[mname] != nil
				raise Exception.new("cannot define two overriding methods for #{mname}\n")
			end
			@prev_overriden[mname] = true
		end
	end
	def override_prev_commit
		@prev_overriden.each_key do |mname|
			alias_method "__new_" + mname.to_s, mname
			module_eval %Q{
				def #{"org_" + mname.to_s} (*args, &proc)
					k = "__#{name}__original__"
					if Thread.current[k] == nil
						Thread.current[k] = 0
					end
					Thread.current[k] += 1
					begin
						#{"__org_" + mname.to_s}(*args, &proc)
					ensure
						Thread.current[k] -= 1
					end
				end
				def #{mname} (*args, &proc)
					k = "__#{name}__original__"
					if Thread.current[k] == nil
						Thread.current[k] = 0
					end
					if Thread.current[k] > 0
						#{"__org_" + mname.to_s}(*args, &proc)
					else
						#{"__new_" + mname.to_s}(*args, &proc)
					end
				end
			}
		end
	end
end


