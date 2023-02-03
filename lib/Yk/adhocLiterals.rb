
class String
	def ssubst rg, str, anot
		@anotList ||= [nil] * size
		ed = rg.exclude_end? ? rg.end - 1 : rg.end
		tail = [[anot, rg.begin]] * str.size + @anotList[ed + 1 .. -1]
		@anotList[rg.begin .. -1] = tail
		self[rg] = str
	end
	def anot i
		@anotList ? nil : @anotList[i] 
	end
end

class AdhocLiterals
	Literals = {}
	class Error < Exception
	end
	def self.[] arg
		Literals[arg]
	end
	def self.resolveRequirements opts
		Opts.merge opts
		if opts[:adhoc_literals].is_a? Array
			opts[:adhoc_literals].each do |s|
				e = File.expand_path(__FILE__)
				d = File.dirname(e)
				sd = File.basename(e, ".rb")
				begin
					Literals[s] = true
					require  "#{d}/#{sd}/" + s.to_s.downcase
				rescue
					raise Error.new("Adhoc literal, #{s} is not defined")
				end
			end
		end
	end
	def self.require arg
		e = File.expand_path(__FILE__)
		d = File.dirname(e)
		sd = File.basename(e, ".rb")
		require  "#{d}/#{sd}/" + arg
	end
end

=begin
				res = 25 * g.foo "\r\n" \ ln
							case ln
							when 3
								break 1
							when 4
								break 2
						_ .to_i + 5
				def test

				end
				doc = <<>
					!ENTITY open-hatch
						asdf
						asdf2
						asdf3
					<html
						`foo
						<table class=asdf
							10.times
								<tr height=1
									<td width=3
										<div id=subdoc
											`#{_1}
									<td
										2
										5.times
											test
										3
										<input type=button onClick=test 
										<input type=text name=a accessor
									<td

						`pqr
						!--
							comment
				def doc.test # direct
					subdoc.innerHTML = <H2
						`This is test
					a.value = "success"
					but1.enabled = false
				doc.__defun__ :testAjax
					doc.subdoc.innerHTML = getFooDocElem #if not defined in doc, request Ajax by XMLHttpRequest
				asdf
					_1 + _1
				_
					_1 + _1
				Fiber.fork
					doc.show
				while
					sleep 10
					doc.byId.subdoc.innerHTML = <H2
						``Time.now
					doc.byId.
					
					def expect &c
	lp:						loop buff += getc rescue break
							all_not_match = true
							c.when.each \ *args, bl
								args.each \ r
									buff =~ r
									case $/.status
									when :partial
										all_not_match &&= false
									when :complete
										bl.call
										buff.clear
										lp.next
							if all_not_match
								c.else&.call
								buff.clear





					`ls -la`.open 2, [1, 0] => :tty, timeout: 5, status: ^es \ ferr, ftty
						fork
							ferr.expect \ e
								e.when /(^|\n)password:/
									ftty.write pwd
								e.else
									printerr _1
						lns = ftty.lines
					if cmd.exitstatus != 0
						
					

					# 1. a = /*1*/ 1	# is comment 'cause the comment closed witin a line
					# 1'. a = /"*1*"/	# is a path '/*1*/'
					# 2. a = /*			# is comment beginning
					# 2. a, b = /*, /*	# the first '/*' is path, second is comment beginning
					# 2'. a = /"*"		# is a path, '/*'
					# 3. a = /etc/*		# is a path, '/etc/*'
=end
=begin
		# opts : 	tab, tabstop, tab_stop
		# 			underscore_line_continuation
		# 			block_label
		# 			omittable_if, omittable_do
		# 			c_comment
		#			nested_when
		# 			adhoc_pathname
		# 			url
		# 			ip
		# 			safe_cmd
		#			SLASH_NOT_REG_NOR_PATH = ROOT_PATH | REG_EXPR # DIVIDE OPERATOR
		#			IS_SUBJECT = /\s+(\.\w|\#|\/\*)|\s*((\,|\:|\;)(?!<SLASH_NOT_REG_NOR_PATH>)|(\}|\]|\))(?!<REG_END>))|$/
		#			REG_END = /\/[uesnimxo]+(?=<IS_SUBJECT>)/
		#			ROOT_PATH = /\/([\w\d\.\*\?\-]+|)(?=<IS_SUBJECT>)/
		#			PATH_OR_REG
		#			PATH
		#			REG
		#			<PATH> , .\w+ / ; : } ] ) /\s
		#			x = [/, /asd, /foo]
		#			x = /			# path
		#			x = / /	foo		# path => Pathname.new("/") / foo
		#			x, y = /, / foo /		# path => Pathname.new("/") / foo
		#			/ foo /
		#			/etc		# path
		# 			someResult = foo /proc, /, sys, /etc/, /bin/ /* comment */
		while expr =~ /
					::`									# possible unclosed `
				|	:`									# possible unclosed `
				|	:\/									# possible unclosed \/
				|	\.+\/								# path
				|	\.									# possible unclosed ` ; maybe over comment ".."
														# or possible reserved word as method name
				|	\bend\b
				|	\bdef\b								# possible unclosed ` ; maybe over comment
				|	\b(?<reserved>(class|module|if|unless|while|until|for|rescue|ensure|else|elsif|case|when|in|then|do))\b
				|	\b__DATA__\b
				|	\w[\w\d]*
				|	\$[\/'`"%]							# possible unclosed
				|	;
				|	(?<bracket_start>[({[])
				|	(?<space>[\t\r\f\v\x20]+)
				|	\\\n
				|	(?<ln>(\n|$))
				|	\b_\b
				|	(?<comment>\#.*(\n|$))				# traditional style comment, interpreted as new line
				|	(?<c_comment>\/\*.*?\*\/)			# c comment, interpreted as space
				|	\/\*								# c comment start
				|	\`
				|	\'
				|	\"
				|	\/\n					            # regular expression
				|	\/(?![$\s])	       					# regular expression or ad hoc file path
				|	\<\<(~|-|)([\'\"\`]|)\w+			# line literal
				|	\%([a-zA-Z]|)([^\w\s]|_)			# percent expression
				|	\d+\.\d+
				|	\W+
			/x
=end
