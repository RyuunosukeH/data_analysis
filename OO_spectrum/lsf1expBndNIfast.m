classdef lsf1expBndNIfast < lsf1expNIfast & lineshapeFunctionBnd
   properties
       
   end
   
   methods
       function obj = lsf1expBndNIfast(params,str,aRFoptions)
            if nargin == 0;
                super_args = {};
            else
                super_args{1} = params;
                super_args{2} = str;
                super_args{3} = aRFoptions;
            end
            obj@lineshapeFunctionBnd(super_args);
            obj = obj.maketpoints(aRFoptions);
        end
 
   end
   
end