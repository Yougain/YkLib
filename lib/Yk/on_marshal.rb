
module OnMarshal
    def marshal_dump
       	if respond_to? :on_marshal_dump
       		on_marshal_dump
       	end
       	Marshal::dump(self.instance_variables.collect{|var| [var, instance_variable_get(var)]})
    end
    def marshal_load(obj)
        Marshal::load(obj).each{ |value|
       		instance_variable_set(value[0], value[1])
        }
       	if respond_to? :on_marshal_load
       		on_marshal_load
       	end
    end
end



