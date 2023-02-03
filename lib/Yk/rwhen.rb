

def rwhen (expr, diffSec = 0)
	while true
		yield
		waitSec = nil
		IO.popen "rwhen.rb '#{expr}' #{$PROGRAM_NAME}" do |fr|
			waitSec = (fr.gets || break).chomp.to_f
		end
		if $?.to_i != 0 || waitSec == nil
			raise ArgumentError.new("failed to calculate the execution time by rwhen\n")
		end
		if $DEBUG
			require 'Yk/debugout'
			er waitSec + diffSec
		end
		sleep waitSec + diffSec
	end
end


