function [tau_c,stde_tau_c] = correlationTime_0to250(cfit_obj)
%for MY code, it would be [tau_c,stde_tau_c]=correlationTime(CFFit(model#).fitresult)
% calculate the correlation time
tau_c = integrate(cfit_obj,250,0);

% calculate the standard deviation of the correlation time

% finding the locations of our amplitudes and times in the fit for
% later (this 'should' be consistent, but I'd rather checks, since
% that'd be a disgusting thing to mess up.
names = coeffnames(cfit_obj);
% times
tTest = regexp(names,'t[12345]');
ind1 = ~cellfun(@isempty,tTest);
% amplitudes
aTest = regexp(names,'a[12345]');
ind2 = ~cellfun(@isempty,aTest);

ind = ind1 + ind2;
if sum(~ind) >0
    error('Variable naming format is incorrect.')
end

% making a convenient matrix of coefficient values and standard
% errors
values = coeffvalues(cfit_obj);
CI = confint(cfit_obj);
stde = (CI(2,:)-CI(1,:))./(2*1.96);
coeffMat = [values' stde'];
% and then decomposing it into its time and amplitude components
% I suppose this code will break if amplitudes and times are not in
% the same order ... something to keep in mind for the future
tMat = coeffMat(ind1,:);
aMat = coeffMat(ind2,:);
% Propagation of error from the best fit coefficients
stde_tau_c = sqrt(sum(tMat(:,1).^2.*aMat(:,2).^2 + ...
    aMat(:,1).^2.*tMat(:,2).^2));
