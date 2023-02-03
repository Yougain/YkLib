
require 'Yk/path_aux'


def printRes (arg)
	if arg
		system <<ENDX
. /etc/rc.d/init.d/functions 
success 
echo 
ENDX
	else
		system <<ENDX
. /etc/rc.d/init.d/functions 
failure 
echo 
ENDX
	end
end


def sysinit (*args)
    lFile = "/var/lock/subsys/#{$0.basename}"
	if args.size == 0
		args = ARGV
	end
	case args[0]
	when "start"
		cmdStart = true
	when "stop"
		cmdStop = true
	when "restart"
		cmdStart = true
		cmdStop = true
	when "condstart"
		if !lFile.exist?
			cmdStart = true
		end
	when "condstop"
		if lFile.exist?
			cmdStop = true
		end
	when "condrestart"
		if lFile.exist?
			cmdStart = true
			cmdStop = true
		end
	end
    STDOUT.flush
	if [cmdStart, cmdStop] == [nil, nil]
		print "cannot execute #{$0.basename} #{args[0]}"
		system <<END
. /etc/rc.d/init.d/functions 
failure  
echo 
END
	else
    	if cmdStop
    		cmdStopRes = yield("stop")
			printRes cmdStopRes
		end
		if cmdStart	
    		cmdStartRes = yield("start")
			printRes cmdStartRes
		end
	end
	if cmdStopRes
		lFile.rm_f
	end
	if cmdStartRes
		lFile.touch
	end
end


